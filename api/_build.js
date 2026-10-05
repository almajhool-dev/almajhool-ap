// Turns report content into DOCX / PDF / PPTX / XLSX files with formal academic typesetting.
// Cover (all formats): Iraqi ministry header on the right, institution logo on the left, the heading in red,
// the topic below it, and the students' names in two columns under a red "إعداد الطلاب" / "Prepared by".
import { readFileSync } from "node:fs";
import path from "node:path";
import {
  Document, Packer, Paragraph, TextRun, AlignmentType, HeadingLevel, Footer, PageNumber, ImageRun,
  VerticalAlign, BorderStyle, Table, TableRow, TableCell, WidthType,
  PageBorderDisplay, PageBorderOffsetFrom, PageBorderZOrder,
} from "docx";
import PptxGenJS from "pptxgenjs";
import ExcelJS from "exceljs";
import { PDFDocument, rgb } from "pdf-lib";

const INK = "111111";
const GREY = "5B6475";
const RED = "C00000";
const AR_ORD = ["الأول", "الثاني", "الثالث", "الرابع", "الخامس", "السادس"];
export const MINISTRY = ["جمهورية العراق", "وزارة التعليم العالي والبحث العلمي"];

export function academicYear() {
  const d = new Date();
  const y = d.getUTCFullYear();
  return d.getUTCMonth() >= 8 ? `${y}–${y + 1}` : `${y - 1}–${y}`;
}
const chapterLabel = (r, i) => {
  const word = r.chapterWord || r.L.chapter;
  return r.lang === "ar" ? `${word} ${AR_ORD[i]}` : `${word} ${i + 1}`;
};
const secNum = (ci, si) => `${ci + 1}.${si + 1}`;
const T = (r) => r.theme || { primary: "1F2A44", topic: "000000", border: "none", bg: null };
const headerLines = (r) => [...MINISTRY, r.university, r.college, r.department ? `قسم ${r.department.replace(/^قسم\s+/, "")}` : ""].filter(Boolean);
const byLabel = (r) => (r.lang === "ar" ? (r.students.length > 1 ? "إعداد الطلاب" : "إعداد الطالب") : r.L.by);
const figLabel = (r, n) => (r.lang === "ar" ? `شكل (${n})` : `Figure ${n}`);
/** Names in pairs: first of each pair on the reading-start side (right in Arabic, left otherwise). */
const pairs = (names) => { const out = []; for (let i = 0; i < names.length; i += 2) out.push(names.slice(i, i + 2)); return out; };

/* ------------------------------- DOCX ------------------------------- */
export async function buildDocx(r) {
  const rtl = r.rtl;
  const th = T(r);
  const f = r.fmt || {};
  const bodyFont = f.font || (rtl ? "Simplified Arabic" : "Times New Roman");
  const baseSize = f.sizePt ? Math.round(f.sizePt * 2) : rtl ? 28 : 24;
  const lineRule = f.lineSpacing ? Math.round(f.lineSpacing * 240) : rtl ? 300 : 360;
  const run = (text, o = {}) => new TextRun({
    text, rightToLeft: o.rtl ?? rtl, bold: o.bold, color: o.color || INK,
    size: o.size || baseSize, sizeComplexScript: o.size || baseSize,
    boldComplexScript: o.bold, font: { ascii: o.font || bodyFont, hAnsi: o.font || bodyFont, cs: o.font || bodyFont },
  });
  const para = (text, o = {}) => new Paragraph({
    bidirectional: o.rtl ?? rtl,
    alignment: o.align || (f.align === "right" || f.align === "left" ? (rtl ? AlignmentType.RIGHT : AlignmentType.LEFT) : AlignmentType.JUSTIFIED),
    spacing: { after: o.after ?? 160, before: o.before ?? 0, line: o.line ?? lineRule },
    indent: o.indent ? (rtl ? { firstLine: 567 } : { left: 0, firstLine: 567 }) : undefined,
    heading: o.heading, keepNext: o.keepNext, pageBreakBefore: o.pageBreakBefore, border: o.border,
    children: [run(text, o)],
  });
  const head = Math.max(baseSize, rtl ? 28 : 24);
  const h1 = (text, o = {}) => para(text, { bold: true, size: head + 12, color: th.primary, align: AlignmentType.CENTER, after: 280, before: 120, heading: HeadingLevel.HEADING_1, keepNext: true, pageBreakBefore: o.pageBreakBefore ?? true, line: 300 });
  const h2 = (text) => para(text, { bold: true, size: head + 4, color: th.primary, align: rtl ? AlignmentType.RIGHT : AlignmentType.LEFT, after: 120, before: 240, heading: HeadingLevel.HEADING_2, keepNext: true, line: 300 });
  const body = (text) => para(text, { indent: true });
  const center = AlignmentType.CENTER;
  const none = { style: BorderStyle.NONE, size: 0, color: "FFFFFF" };
  const noBorders = { top: none, bottom: none, left: none, right: none, insideHorizontal: none, insideVertical: none };
  const cell = (children, o = {}) => new TableCell({ children, width: { size: o.w, type: WidthType.DXA }, borders: { top: none, bottom: none, left: none, right: none }, verticalAlign: o.v || VerticalAlign.TOP });
  const ar = (text, o = {}) => para(text, { rtl: true, font: "Simplified Arabic", line: 276, after: 20, ...o });

  // ---- Cover ----
  const cover = [];
  const logoPara = r.logo
    ? new Paragraph({ alignment: AlignmentType.LEFT, children: [new ImageRun({ type: "png", data: r.logo.data, transformation: (() => { const h = 105; const w = Math.min(190, Math.round((r.logo.width / r.logo.height) * h)); return { width: w, height: Math.round(w * r.logo.height / r.logo.width) }; })() })] })
    : new Paragraph({ children: [] });
  const hdr = headerLines(r).map((t, i) => ar(t, { bold: true, size: i < 2 ? 30 : 28, align: AlignmentType.RIGHT, color: INK }));
  cover.push(new Table({
    width: { size: 9070, type: WidthType.DXA }, columnWidths: [5670, 3400], borders: noBorders, visuallyRightToLeft: true,
    rows: [new TableRow({ children: [cell(hdr, { w: 5670 }), cell([logoPara], { w: 3400 })] })],
  }));
  cover.push(para(r.L.report, { align: center, bold: true, size: rtl ? 44 : 36, color: RED, before: 1900, after: 220, line: 300 }));
  cover.push(para(r.title, { align: center, bold: true, size: rtl ? 48 : 40, color: th.topic, after: 120, line: 320 }));
  cover.push(para(byLabel(r), { align: center, bold: true, size: rtl ? 34 : 30, color: RED, before: 1900, after: 160 }));
  const nameRuns = (n) => [para(n, { align: center, bold: true, size: rtl ? 32 : 26, after: 60 })];
  if (r.students.length === 1) cover.push(...nameRuns(r.students[0]));
  else cover.push(new Table({
    width: { size: 9070, type: WidthType.DXA }, columnWidths: [4535, 4535], borders: noBorders, visuallyRightToLeft: rtl,
    rows: pairs(r.students).map((pr) => new TableRow({ children: pr[1]
      ? [cell(nameRuns(pr[0]), { w: 4535 }), cell(nameRuns(pr[1]), { w: 4535 })]
      : [new TableCell({ children: nameRuns(pr[0]), columnSpan: 2, width: { size: 9070, type: WidthType.DXA }, borders: { top: none, bottom: none, left: none, right: none } })] })),
  }));
  if (r.supervisor) cover.push(para(`${r.L.sup}: ${r.supervisor}`, { align: center, bold: true, size: rtl ? 30 : 26, color: th.primary, before: 360, after: 60 }));
  cover.push(para(`${r.L.year}: ${academicYear()}`, { align: center, size: rtl ? 26 : 22, color: GREY, before: 480 }));

  // ---- Contents ----
  const toc = [h1(r.L.toc, { pageBreakBefore: false })];
  const tocLine = (t, lvl) => para(t, { align: rtl ? AlignmentType.RIGHT : AlignmentType.LEFT, after: 60, bold: lvl === 0, color: lvl === 0 ? th.primary : INK, size: lvl === 0 ? baseSize + 2 : baseSize, line: 280 });
  toc.push(tocLine(r.L.intro, 0));
  r.chapters.forEach((c, ci) => {
    toc.push(tocLine(`${chapterLabel(r, ci)}: ${c.title}`, 0));
    c.sections.forEach((s, si) => toc.push(tocLine(`      ${secNum(ci, si)}  ${s.title}`, 1)));
  });
  toc.push(tocLine(r.L.conclusion, 0));
  toc.push(tocLine(r.L.refs, 0));

  // ---- Body ----
  const main = [h1(r.L.intro), ...r.intro.map(body)];
  let fig = 0;
  r.chapters.forEach((c, ci) => {
    main.push(h1(`${chapterLabel(r, ci)}: ${c.title}`));
    c.sections.forEach((s, si) => {
      main.push(h2(`${secNum(ci, si)} ${s.title}`));
      (s.paragraphs || []).forEach((t, pi) => {
        main.push(body(t));
        if (si === 0 && pi === 0 && c.image) {
          fig++;
          const w = 520, h = Math.min(330, Math.round((c.image.height / c.image.width) * w));
          main.push(new Paragraph({ alignment: center, spacing: { before: 160, after: 40 }, keepNext: true, children: [new ImageRun({ type: "jpg", data: c.image.data, transformation: { width: Math.round(h * c.image.width / c.image.height), height: h } })] }));
          main.push(para(`${figLabel(r, fig)}: ${c.title}`, { align: center, size: baseSize - 4, color: GREY, after: 20, line: 260 }));
          main.push(para(c.image.credit, { rtl: false, align: center, size: 16, color: GREY, after: 200, line: 240 }));
        }
      });
    });
  });
  main.push(h1(r.L.conclusion), ...r.conclusion.map(body));
  main.push(h1(r.L.refs));
  r.references.forEach((ref, i) => {
    const isAr = /\p{Script=Arabic}/u.test(ref);
    main.push(new Paragraph({
      bidirectional: isAr, alignment: isAr ? AlignmentType.RIGHT : AlignmentType.LEFT,
      indent: { left: 567, hanging: 567 }, spacing: { after: 120, line: 280 },
      children: [run(`${i + 1}. ${ref}`, { size: baseSize - 2, rtl: isAr, font: isAr ? bodyFont : "Times New Roman" })],
    }));
  });

  const m = f.marginsCm || {};
  const tw = (cm, d) => Math.round(Math.max(1, Math.min(4, cm || d)) * 567);
  const margin = { top: tw(m.top, 2.5), bottom: tw(m.bottom, 2.5), left: tw(m.left, 2.5), right: tw(m.right, 2.5) };
  const frame = (display) => ({
    pageBorders: { display, offsetFrom: PageBorderOffsetFrom.PAGE, zOrder: PageBorderZOrder.BACK },
    ...Object.fromEntries(["pageBorderTop", "pageBorderRight", "pageBorderBottom", "pageBorderLeft"].map((k) => [k, { style: BorderStyle.DOUBLE, size: 6, color: th.primary, space: 24 }])),
  });
  const footer = new Footer({ children: [new Paragraph({ alignment: center, children: [new TextRun({ children: [PageNumber.CURRENT], size: 20, color: GREY })] })] });
  const doc = new Document({
    creator: r.students.join("، "),
    title: r.title,
    background: th.bg ? { color: th.bg } : undefined,
    styles: { default: { document: { run: { font: bodyFont } } } },
    sections: [
      { properties: { page: { margin, borders: th.border !== "none" ? frame(PageBorderDisplay.ALL_PAGES) : undefined } }, children: cover },
      { properties: { page: { margin, pageNumbers: { start: 1 }, borders: th.border === "all" ? frame(PageBorderDisplay.ALL_PAGES) : undefined } }, footers: { default: footer }, children: [...toc, ...main] },
    ],
  });
  return Packer.toBuffer(doc);
}

/* -------------------------------- PDF ------------------------------- */
const FONT_DIRS = [path.join(process.cwd(), "public/fonts"), path.join(process.cwd(), "node_modules/@fontsource/amiri/files"), path.join(process.cwd(), "node_modules/@fontsource/cairo/files")];
const readFont = (file) => {
  for (const d of FONT_DIRS) { try { return readFileSync(path.join(d, file)); } catch {} }
  throw new Error("font missing: " + file);
};
let fontCss;
function fonts() {
  if (fontCss) return fontCss;
  const f = (file) => `url(data:font/woff2;base64,${readFont(file).toString("base64")}) format("woff2")`;
  fontCss = [
    ["Amiri", 400, "amiri-arabic-400-normal.woff2"], ["Amiri", 700, "amiri-arabic-700-normal.woff2"],
    ["Amiri", 400, "amiri-latin-400-normal.woff2"], ["Amiri", 700, "amiri-latin-700-normal.woff2"],
    ["Cairo", 600, "cairo-arabic-600-normal.woff2"], ["Cairo", 700, "cairo-arabic-700-normal.woff2"],
    ["Cairo", 600, "cairo-latin-600-normal.woff2"], ["Cairo", 700, "cairo-latin-700-normal.woff2"],
  ].map(([fam, w, file]) => `@font-face{font-family:"${fam}";font-weight:${w};src:${f(file)};}`).join("\n");
  return fontCss;
}
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

function pdfCss(r) {
  const th = T(r);
  const f = r.fmt || {};
  const m = f.marginsCm || {};
  const mc = (v) => `${Math.max(1, Math.min(4, v || 2.5))}cm`;
  const body = r.rtl ? `"Amiri", serif` : `"Times New Roman", "Amiri", serif`;
  const size = f.sizePt ? `${f.sizePt + (r.rtl ? 1.5 : 0)}pt` : r.rtl ? "15pt" : "12pt";
  const lh = f.lineSpacing ? Math.max(1.3, f.lineSpacing * 1.2) : r.rtl ? 1.75 : 1.6;
  return `${fonts()}
  @page { size: A4; margin: ${mc(m.top)} ${mc(m.right)} ${mc(m.bottom)} ${mc(m.left)}; }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body { font-family: ${body}; color: #111; font-size: ${size}; line-height: ${lh}; direction: ${r.rtl ? "rtl" : "ltr"}; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  h1, h2 { font-family: "Amiri", serif; color: #${th.primary}; }
  h1 { text-align: center; font-size: ${r.rtl ? "21pt" : "17pt"}; margin: 0 0 18pt; page-break-before: always; break-after: avoid; }
  h1.first { page-break-before: auto; }
  h2 { font-size: ${r.rtl ? "17pt" : "13.5pt"}; margin: 16pt 0 6pt; break-after: avoid; }
  p { text-align: ${f.align === "right" || f.align === "left" ? "start" : "justify"}; text-indent: 1cm; margin: 0 0 8pt; orphans: 3; widows: 3; }
  figure { margin: 10pt 0 14pt; text-align: center; break-inside: avoid; }
  figure img { max-width: 100%; max-height: 9cm; border-radius: 2pt; }
  figcaption { font-size: 10.5pt; color: #${GREY}; line-height: 1.4; margin-top: 4pt; }
  figcaption small { display: block; font-size: 8pt; direction: ltr; }
  .refs p { text-indent: 0; text-align: start; font-size: ${r.rtl ? "13pt" : "11pt"}; padding-inline-start: 1cm; text-indent: -1cm; word-break: break-word; }
  .refs p.ltr { direction: ltr; text-align: left; font-family: "Times New Roman", "Amiri", serif; }
  .toc div { margin: 3pt 0; }
  .toc .c { font-weight: 700; color: #${th.primary}; margin-top: 7pt; }
  .toc .s { padding-inline-start: 1cm; }
  .cover { height: 24.5cm; display: flex; flex-direction: column; text-align: center; padding: 0.2cm 0; }
  .cover .top { display: flex; flex-direction: row; justify-content: space-between; align-items: flex-start; direction: rtl; }
  .cover .min { text-align: right; font-weight: 700; font-size: 15pt; line-height: 1.55; font-family: "Amiri", serif; }
  .cover .min div:nth-child(-n+2) { font-size: 16pt; }
  .cover .logo img { max-height: 3.4cm; max-width: 5.5cm; object-fit: contain; }
  .cover .mid { flex: 1; display: flex; flex-direction: column; justify-content: center; }
  .cover .lbl { color: #${RED}; font-weight: 700; font-size: ${r.rtl ? "24pt" : "20pt"}; margin-bottom: 10pt; }
  .cover .title { color: #${th.topic}; font-weight: 700; font-size: ${r.rtl ? "26pt" : "22pt"}; line-height: 1.45; max-width: 15cm; margin: 0 auto; }
  .cover .by { color: #${RED}; font-weight: 700; font-size: ${r.rtl ? "18pt" : "16pt"}; margin-bottom: 6pt; }
  .cover .names { display: grid; grid-template-columns: 1fr 1fr; gap: 4pt 1cm; font-weight: 700; font-size: ${r.rtl ? "16pt" : "14pt"}; direction: ${r.rtl ? "rtl" : "ltr"}; }
  .cover .names.one { grid-template-columns: 1fr; }
  .cover .names div:last-child:nth-child(odd) { grid-column: 1 / -1; }
  .cover .sup { margin-top: 12pt; font-weight: 700; color: #${th.primary}; font-size: ${r.rtl ? "15pt" : "13pt"}; }
  .cover .year { margin-top: 14pt; color: #${GREY}; font-size: 12pt; }`;
}

function coverHtml(r) {
  const names = r.students.map((n) => `<div>${esc(n)}</div>`).join("");
  return `<!doctype html><html lang="${r.lang}" dir="${r.rtl ? "rtl" : "ltr"}"><head><meta charset="utf-8"><style>${pdfCss(r)}</style></head><body>
  <div class="cover">
    <div class="top">
      <div class="min">${headerLines(r).map((t) => `<div>${esc(t)}</div>`).join("")}</div>
      <div class="logo">${r.logo ? `<img src="data:image/png;base64,${r.logo.data.toString("base64")}" alt="">` : ""}</div>
    </div>
    <div class="mid"><div class="lbl">${esc(r.L.report)}</div><div class="title">${esc(r.title)}</div></div>
    <div><div class="by">${esc(byLabel(r))}</div><div class="names${r.students.length === 1 ? " one" : ""}">${names}</div>
      ${r.supervisor ? `<div class="sup">${esc(r.L.sup)}: ${esc(r.supervisor)}</div>` : ""}
      <div class="year">${esc(r.L.year)}: ${academicYear()}</div></div>
  </div></body></html>`;
}

function bodyHtml(r) {
  const P = (arr) => (arr || []).map((t) => `<p>${esc(t)}</p>`).join("");
  let toc = `<div class="c">${esc(r.L.intro)}</div>`;
  let main = `<h1>${esc(r.L.intro)}</h1>${P(r.intro)}`;
  let fig = 0;
  r.chapters.forEach((c, ci) => {
    toc += `<div class="c">${esc(chapterLabel(r, ci))}: ${esc(c.title)}</div>` + c.sections.map((s, si) => `<div class="s">${secNum(ci, si)}&nbsp;&nbsp;${esc(s.title)}</div>`).join("");
    main += `<h1>${esc(chapterLabel(r, ci))}: ${esc(c.title)}</h1>` + c.sections.map((s, si) => {
      const paras = (s.paragraphs || []).map((t, pi) => {
        let html = `<p>${esc(t)}</p>`;
        if (si === 0 && pi === 0 && c.image) {
          fig++;
          html += `<figure><img src="data:image/jpeg;base64,${c.image.data.toString("base64")}" alt=""><figcaption>${esc(figLabel(r, fig))}: ${esc(c.title)}<small>${esc(c.image.credit)}</small></figcaption></figure>`;
        }
        return html;
      }).join("");
      return `<h2>${secNum(ci, si)} ${esc(s.title)}</h2>${paras}`;
    }).join("");
  });
  toc += `<div class="c">${esc(r.L.conclusion)}</div><div class="c">${esc(r.L.refs)}</div>`;
  const refs = r.references.map((x, i) => `<p class="${/\p{Script=Arabic}/u.test(x) ? "" : "ltr"}">${i + 1}. ${esc(x)}</p>`).join("");
  main += `<h1>${esc(r.L.conclusion)}</h1>${P(r.conclusion)}<h1>${esc(r.L.refs)}</h1><div class="refs">${refs}</div>`;
  return `<!doctype html><html lang="${r.lang}" dir="${r.rtl ? "rtl" : "ltr"}"><head><meta charset="utf-8"><style>${pdfCss(r)}</style></head><body>
  <h1 class="first">${esc(r.L.toc)}</h1><div class="toc">${toc}</div>${main}</body></html>`;
}

export async function buildPdf(r, { browserFactory } = {}) {
  let browser;
  if (browserFactory) browser = await browserFactory();
  else {
    const chromium = (await import("@sparticuz/chromium")).default;
    const puppeteer = (await import("puppeteer-core")).default;
    browser = await puppeteer.launch({ args: chromium.args, executablePath: await chromium.executablePath(), headless: true });
  }
  try {
    const page = await browser.newPage();
    await page.setJavaScriptEnabled(false); // generated content is static; no scripts may run
    await page.setRequestInterception(true);
    page.on("request", (req) => (req.url().startsWith("data:") || req.url() === "about:blank" ? req.continue() : req.abort()));
    const render = async (html, footer) => {
      await page.setContent(html, { waitUntil: "load" });
      await page.evaluateHandle("document.fonts.ready").catch(() => {});
      return page.pdf({
        format: "A4", printBackground: true, preferCSSPageSize: true,
        displayHeaderFooter: footer,
        headerTemplate: "<span></span>",
        footerTemplate: `<div style="width:100%;text-align:center;font-size:9pt;color:#${GREY};font-family:serif"><span class="pageNumber"></span></div>`,
      });
    };
    const coverPdf = await render(coverHtml(r), false);
    const bodyPdf = await render(bodyHtml(r), true);
    // Page colour and frame are painted on the full sheet (Chrome only paints inside the margins),
    // then the rendered page is placed on top as a vector form, so text stays selectable.
    const th = T(r);
    const hex = (h) => rgb(parseInt(h.slice(0, 2), 16) / 255, parseInt(h.slice(2, 4), 16) / 255, parseInt(h.slice(4, 6), 16) / 255);
    const out = await PDFDocument.create();
    const parts = [[coverPdf, th.border !== "none"], [bodyPdf, th.border === "all"]];
    for (const [src, framed] of parts) {
      const doc = await PDFDocument.load(src);
      if (!th.bg && !framed) { (await out.copyPages(doc, doc.getPageIndices())).forEach((p) => out.addPage(p)); continue; }
      const embedded = await out.embedPages(doc.getPages());
      for (const ep of embedded) {
        const page = out.addPage([ep.width, ep.height]);
        if (th.bg) page.drawRectangle({ x: 0, y: 0, width: ep.width, height: ep.height, color: hex(th.bg) });
        page.drawPage(ep, { x: 0, y: 0 });
        if (framed) {
          const c = hex(th.primary);
          page.drawRectangle({ x: 24, y: 24, width: ep.width - 48, height: ep.height - 48, borderColor: c, borderWidth: 2.2 });
          page.drawRectangle({ x: 29, y: 29, width: ep.width - 58, height: ep.height - 58, borderColor: c, borderWidth: 0.7 });
        }
      }
    }
    out.setTitle(r.title);
    out.setAuthor(r.students.join("، "));
    return Buffer.from(await out.save());
  } finally {
    await browser.close();
  }
}

/* -------------------------------- PPTX ------------------------------ */
export async function buildPptx(r) {
  const th = T(r);
  const pptx = new PptxGenJS();
  pptx.layout = "LAYOUT_WIDE"; // 13.33 x 7.5 in
  pptx.rtlMode = r.rtl;
  pptx.title = r.title;
  pptx.author = r.students.join("، ");
  const font = r.rtl ? "Simplified Arabic" : "Georgia";
  const align = r.rtl ? "right" : "left";
  const base = { fontFace: font, color: INK, rtlMode: r.rtl };
  const bg = { color: th.bg || "FFFFFF" };
  const frameObjs = th.border === "all" ? [{ rect: { x: 0.18, y: 0.18, w: 12.97, h: 7.14, fill: { type: "none" }, line: { color: th.primary, width: 2.5 } } }] : [];

  pptx.defineSlideMaster({
    title: "BODY", background: bg,
    objects: [
      ...frameObjs,
      { rect: { x: 0, y: 0, w: 13.33, h: 0.12, fill: { color: th.primary } } },
      { line: { x: 0.7, y: 1.35, w: 11.93, h: 0, line: { color: "C9CEDA", width: 1 } } },
    ],
    slideNumber: { x: 6.4, y: 7.0, w: 0.6, h: 0.3, fontSize: 10, color: GREY, align: "center" },
  });

  // Title slide: ministry header right, logo left, red heading, topic, names in two columns.
  const t = pptx.addSlide();
  t.background = bg;
  if (th.border !== "none") t.addShape(pptx.ShapeType.rect, { x: 0.18, y: 0.18, w: 12.97, h: 7.14, fill: { type: "none" }, line: { color: th.primary, width: 2.5 } });
  t.addText(headerLines(r).map((x, i) => ({ text: x, options: { breakLine: true, fontSize: i < 2 ? 16 : 14 } })),
    { fontFace: "Simplified Arabic", rtlMode: true, bold: true, color: INK, x: 6.4, y: 0.35, w: 6.5, h: 1.7, align: "right", valign: "top" });
  if (r.logo) {
    const h = 1.5, w = Math.min(3, (r.logo.width / r.logo.height) * h);
    t.addImage({ data: `data:image/png;base64,${r.logo.data.toString("base64")}`, x: 0.5, y: 0.35, w, h });
  }
  t.addText(r.L.report, { ...base, x: 1, y: 2.25, w: 11.33, h: 0.7, fontSize: 26, bold: true, color: RED, align: "center" });
  t.addText(r.title, { ...base, x: 1, y: 2.95, w: 11.33, h: 1.4, fontSize: 32, bold: true, color: th.topic, align: "center", valign: "middle" });
  t.addText(byLabel(r), { ...base, x: 1, y: 4.55, w: 11.33, h: 0.5, fontSize: 20, bold: true, color: RED, align: "center" });
  const rows = pairs(r.students);
  rows.forEach((pr, i) => {
    const y = 5.05 + i * 0.42;
    if (pr.length === 1) t.addText(pr[0], { ...base, x: 1, y, w: 11.33, h: 0.42, fontSize: 18, bold: true, align: "center" });
    else {
      const [first, second] = pr;
      const startX = r.rtl ? 6.9 : 1.2, otherX = r.rtl ? 1.2 : 6.9;
      t.addText(first, { ...base, x: startX, y, w: 5.2, h: 0.42, fontSize: 17, bold: true, align: "center" });
      if (second) t.addText(second, { ...base, x: otherX, y, w: 5.2, h: 0.42, fontSize: 17, bold: true, align: "center" });
    }
  });
  const yEnd = 5.1 + rows.length * 0.42;
  t.addText([
    ...(r.supervisor ? [{ text: `${r.L.sup}: ${r.supervisor}`, options: { breakLine: true, bold: true, color: th.primary } }] : []),
    { text: `${r.L.year}: ${academicYear()}`, options: { color: GREY, fontSize: 13 } },
  ], { ...base, x: 1, y: Math.min(6.4, yEnd), w: 11.33, h: 0.85, fontSize: 16, align: "center" });

  const content = (title, bullets) => {
    const s = pptx.addSlide({ masterName: "BODY" });
    s.addText(title, { ...base, x: 0.7, y: 0.35, w: 11.93, h: 0.9, fontSize: 28, bold: true, color: th.primary, align, valign: "middle" });
    s.addText(bullets.map((b) => ({ text: b, options: { bullet: { indent: 18 }, breakLine: true, paraSpaceAfter: 10 } })),
      { ...base, x: 0.8, y: 1.6, w: 11.73, h: 5.2, fontSize: 20, align, valign: "top", lineSpacingMultiple: 1.1 });
  };
  const toc = [r.L.intro, ...r.chapters.map((c, i) => `${chapterLabel(r, i)}: ${c.title}`), r.L.conclusion, r.L.refs];
  content(r.L.toc, toc);
  content(r.L.intro, r.intro.slice(0, 5));
  r.chapters.forEach((c, ci) => {
    const d = pptx.addSlide();
    d.background = { color: th.primary };
    const txt = [{ text: chapterLabel(r, ci), options: { fontSize: 20, color: "D9DEE8", breakLine: true } }, { text: c.title, options: { fontSize: 32, bold: true, color: "FFFFFF" } }];
    if (c.image) {
      const h = 4.6, w = Math.min(6.2, (c.image.width / c.image.height) * h);
      const imgX = r.rtl ? 0.6 : 13.33 - 0.6 - w;
      d.addImage({ data: `data:image/jpeg;base64,${c.image.data.toString("base64")}`, x: imgX, y: 1.2, w, h: w * c.image.height / c.image.width });
      d.addText(c.image.credit, { x: imgX, y: 1.25 + w * c.image.height / c.image.width, w, h: 0.3, fontSize: 9, color: "C9CEDA", fontFace: "Arial", align: "center" });
      d.addText(txt, { ...base, x: r.rtl ? 7.1 : 0.6, y: 1.6, w: 5.7, h: 4, align, valign: "middle" });
    } else d.addText(txt, { ...base, x: 1, y: 2.4, w: 11.33, h: 2.6, align: "center", valign: "middle" });
    c.sections.forEach((s, si) => content(`${secNum(ci, si)} ${s.title}`, (s.bullets || []).slice(0, 5)));
  });
  content(r.L.conclusion, r.conclusion.slice(0, 5));
  const per = 6;
  for (let i = 0; i < Math.max(1, r.references.length); i += per) {
    const refs = pptx.addSlide({ masterName: "BODY" });
    refs.addText(r.L.refs, { ...base, x: 0.7, y: 0.35, w: 11.93, h: 0.9, fontSize: 28, bold: true, color: th.primary, align });
    refs.addText(r.references.slice(i, i + per).map((x, k) => {
      const isAr = /\p{Script=Arabic}/u.test(x);
      return { text: `${i + k + 1}. ${x}`, options: { breakLine: true, paraSpaceAfter: 6, rtlMode: isAr, align: isAr ? "right" : "left", fontFace: isAr ? font : "Georgia" } };
    }), { ...base, x: 0.8, y: 1.55, w: 11.73, h: 5.3, fontSize: 13, valign: "top" });
  }
  return Buffer.from(await pptx.write({ outputType: "nodebuffer" }));
}

/* -------------------------------- XLSX ------------------------------ */
export async function buildXlsx(r) {
  const th = T(r);
  const wb = new ExcelJS.Workbook();
  wb.creator = r.students.join("، ");
  wb.title = r.title;
  const font = r.rtl ? "Simplified Arabic" : "Times New Roman";
  const ws = wb.addWorksheet(r.L.report.slice(0, 28) || "Report", { views: [{ rightToLeft: r.rtl, state: "frozen", ySplit: 12 }], pageSetup: { paperSize: 9, orientation: "portrait", fitToPage: true, fitToWidth: 1, fitToHeight: 0, margins: { left: 0.98, right: 0.98, top: 0.98, bottom: 0.98, header: 0.3, footer: 0.3 } } });
  ws.columns = [{ width: 8 }, { width: 34 }, { width: 110 }];
  const fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF" + th.primary } };
  const wrap = { wrapText: true, vertical: "top", horizontal: r.rtl ? "right" : "left", readingOrder: r.rtl ? "rtl" : "ltr" };
  const add = (vals, style = {}) => {
    const row = ws.addRow(vals);
    row.eachCell((c) => { c.font = { name: font, size: style.size || 14, bold: style.bold, color: { argb: style.color || "FF111111" } }; c.alignment = style.align || wrap; if (style.fill) c.fill = style.fill; });
    return row;
  };
  const merged = (text, style) => { const row = add(["", text, ""], style); ws.mergeCells(row.number, 2, row.number, 3); return row; };
  headerLines(r).forEach((x) => merged(x, { bold: true, size: 14, align: { horizontal: "right", readingOrder: "rtl" } }));
  merged(r.L.report, { bold: true, size: 16, color: "FF" + RED, align: { horizontal: "center" } });
  merged(r.title, { bold: true, size: 20, color: "FF" + th.topic, align: { horizontal: "center", wrapText: true } }).height = 40;
  merged(byLabel(r), { bold: true, color: "FF" + RED, align: { horizontal: "center" } });
  merged(r.students.join("    ·    "), { bold: true, align: { horizontal: "center", wrapText: true } });
  merged(`${r.supervisor ? `${r.L.sup}: ${r.supervisor}    ` : ""}${r.L.year}: ${academicYear()}`, { color: "FF" + GREY, align: { horizontal: "center" } });
  const head = add(["#", r.lang === "ar" ? "العنوان" : "Heading", r.lang === "ar" ? "النص" : "Text"], { bold: true, color: "FFFFFFFF", fill });
  head.height = 24;
  const estHeight = (t) => Math.min(409, Math.max(22, Math.ceil(String(t).length / 95) * 21));
  const block = (num, heading, paras) => paras.forEach((t, i) => { const rw = add([i ? "" : num, i ? "" : heading, t]); rw.height = estHeight(t); rw.getCell(2).font = { name: font, size: 14, bold: true, color: { argb: "FF" + th.primary } }; });
  block("—", r.L.intro, r.intro);
  r.chapters.forEach((c, ci) => {
    const ch = add([String(ci + 1), `${chapterLabel(r, ci)}: ${c.title}`, ""], { bold: true, size: 15, color: "FF" + th.primary, fill: { type: "pattern", pattern: "solid", fgColor: { argb: "FFE8EBF2" } } });
    ws.mergeCells(ch.number, 2, ch.number, 3);
    c.sections.forEach((s, si) => block(secNum(ci, si), s.title, s.paragraphs || []));
  });
  block("—", r.L.conclusion, r.conclusion);

  const rs = wb.addWorksheet(r.L.refs.slice(0, 28), { views: [{ rightToLeft: false }] });
  rs.columns = [{ width: 6 }, { width: 140 }];
  rs.addRow(["#", r.L.refs]).eachCell((c) => { c.font = { name: font, bold: true, color: { argb: "FFFFFFFF" } }; c.fill = fill; });
  r.references.forEach((x, i) => {
    const rw = rs.addRow([i + 1, x]);
    const isAr = /\p{Script=Arabic}/u.test(x);
    rw.getCell(2).alignment = { wrapText: true, vertical: "top", horizontal: isAr ? "right" : "left", readingOrder: isAr ? "rtl" : "ltr" };
    rw.height = estHeight(x);
  });
  return Buffer.from(await wb.xlsx.writeBuffer());
}
