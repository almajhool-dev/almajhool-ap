// Turns report content into DOCX / PDF / PPTX / XLSX files with formal academic typesetting.
import { readFileSync } from "node:fs";
import path from "node:path";
import {
  Document, Packer, Paragraph, TextRun, AlignmentType, HeadingLevel, Footer, PageNumber, ImageRun, PageBreak,
  VerticalAlign, BorderStyle,
} from "docx";
import PptxGenJS from "pptxgenjs";
import ExcelJS from "exceljs";
import { PDFDocument } from "pdf-lib";

const NAVY = "1F2A44";
const INK = "111111";
const GREY = "5B6475";
const AR_ORD = ["الأول", "الثاني", "الثالث", "الرابع", "الخامس", "السادس"];

export function academicYear() {
  const d = new Date();
  const y = d.getUTCFullYear();
  return d.getUTCMonth() >= 8 ? `${y}–${y + 1}` : `${y - 1}–${y}`;
}
const chapterLabel = (r, i) => (r.lang === "ar" ? `${r.L.chapter} ${AR_ORD[i]}` : `${r.L.chapter} ${i + 1}`);
const secNum = (ci, si) => `${ci + 1}.${si + 1}`;

/* ------------------------------- DOCX ------------------------------- */
export async function buildDocx(r) {
  const rtl = r.rtl;
  const bodyFont = rtl ? "Traditional Arabic" : "Times New Roman";
  const headFont = rtl ? "Traditional Arabic" : "Times New Roman";
  const run = (text, o = {}) => new TextRun({
    text, rightToLeft: rtl, bold: o.bold, color: o.color || INK,
    size: o.size || (rtl ? 32 : 24), sizeComplexScript: o.size || (rtl ? 32 : 24),
    boldComplexScript: o.bold, font: { ascii: o.font || bodyFont, hAnsi: o.font || bodyFont, cs: o.font || bodyFont },
  });
  const para = (text, o = {}) => new Paragraph({
    bidirectional: rtl,
    alignment: o.align || AlignmentType.JUSTIFIED,
    spacing: { after: o.after ?? 160, before: o.before ?? 0, line: o.line ?? (rtl ? 300 : 360) },
    indent: o.indent ? (rtl ? { right: 567 } : { left: 0, firstLine: 567 }) : undefined,
    heading: o.heading,
    keepNext: o.keepNext,
    pageBreakBefore: o.pageBreakBefore,
    border: o.border,
    children: [run(text, o)],
  });
  const h1 = (text, o = {}) => para(text, { bold: true, size: rtl ? 40 : 32, color: NAVY, font: headFont, align: AlignmentType.CENTER, after: 280, before: 120, heading: HeadingLevel.HEADING_1, keepNext: true, pageBreakBefore: o.pageBreakBefore ?? true });
  const h2 = (text) => para(text, { bold: true, size: rtl ? 34 : 26, color: NAVY, font: headFont, align: rtl ? AlignmentType.RIGHT : AlignmentType.LEFT, after: 120, before: 240, heading: HeadingLevel.HEADING_2, keepNext: true });
  const body = (text) => para(text, { indent: true });
  const center = AlignmentType.CENTER;

  // Cover
  const cover = [];
  if (r.logo) {
    const h = 110, w = Math.round((r.logo.width / r.logo.height) * h);
    cover.push(new Paragraph({ alignment: center, spacing: { after: 240 }, children: [new ImageRun({ type: "png", data: r.logo.data, transformation: { width: Math.min(w, 260), height: h } })] }));
  }
  cover.push(para(r.university, { align: center, bold: true, size: rtl ? 36 : 30, color: NAVY, after: 60 }));
  if (r.department) cover.push(para(`${r.L.dept}: ${r.department}`, { align: center, size: rtl ? 30 : 24, color: GREY, after: 600 }));
  cover.push(para(r.L.report, { align: center, size: rtl ? 30 : 24, color: GREY, after: 120, before: 600 }));
  cover.push(para(r.title, {
    align: center, bold: true, size: rtl ? 52 : 40, color: NAVY, after: 700,
    border: { top: { style: BorderStyle.SINGLE, size: 6, color: NAVY, space: 12 }, bottom: { style: BorderStyle.SINGLE, size: 6, color: NAVY, space: 12 } },
  }));
  cover.push(para(`${r.L.by}: ${r.student}`, { align: center, size: rtl ? 32 : 26, after: 100 }));
  if (r.supervisor) cover.push(para(`${r.L.sup}: ${r.supervisor}`, { align: center, size: rtl ? 32 : 26, after: 100 }));
  cover.push(para(`${r.L.year}: ${academicYear()}`, { align: center, size: rtl ? 28 : 22, color: GREY, before: 700 }));

  // Contents
  const toc = [h1(r.L.toc, { pageBreakBefore: false })];
  const tocLine = (t, lvl) => para(t, { align: rtl ? AlignmentType.RIGHT : AlignmentType.LEFT, after: 60, bold: lvl === 0, color: lvl === 0 ? NAVY : INK, indent: false, size: lvl === 0 ? (rtl ? 30 : 24) : (rtl ? 28 : 22) });
  toc.push(tocLine(r.L.intro, 0));
  r.chapters.forEach((c, ci) => {
    toc.push(tocLine(`${chapterLabel(r, ci)}: ${c.title}`, 0));
    c.sections.forEach((s, si) => toc.push(tocLine(`      ${secNum(ci, si)}  ${s.title}`, 1)));
  });
  toc.push(tocLine(r.L.conclusion, 0));
  toc.push(tocLine(r.L.refs, 0));

  const main = [h1(r.L.intro), ...r.intro.map(body)];
  r.chapters.forEach((c, ci) => {
    main.push(h1(`${chapterLabel(r, ci)}: ${c.title}`));
    c.sections.forEach((s, si) => { main.push(h2(`${secNum(ci, si)} ${s.title}`)); (s.paragraphs || []).forEach((t) => main.push(body(t))); });
  });
  main.push(h1(r.L.conclusion), ...r.conclusion.map(body));
  main.push(h1(r.L.refs));
  r.references.forEach((ref) => main.push(new Paragraph({
    bidirectional: rtl, alignment: rtl ? AlignmentType.RIGHT : AlignmentType.LEFT,
    indent: rtl ? { right: 567, hanging: 567 } : { left: 567, hanging: 567 }, spacing: { after: 120, line: 300 },
    children: [run(ref, { size: rtl ? 28 : 22 })],
  })));

  const margin = { top: 1417, bottom: 1417, left: 1417, right: 1417 }; // 2.5 cm
  const footer = new Footer({ children: [new Paragraph({ alignment: center, children: [new TextRun({ children: [PageNumber.CURRENT], size: 20, color: GREY })] })] });
  const doc = new Document({
    creator: r.student,
    title: r.title,
    styles: { default: { document: { run: { font: bodyFont } } } },
    sections: [
      { properties: { page: { margin }, verticalAlign: VerticalAlign.CENTER }, children: cover },
      { properties: { page: { margin, pageNumbers: { start: 1 } } }, footers: { default: footer }, children: [...toc, ...main] },
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
  const body = r.rtl ? `"Amiri", serif` : `"Times New Roman", "Amiri", serif`;
  return `${fonts()}
  @page { size: A4; margin: 2.5cm; }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body { font-family: ${body}; color: #111; font-size: ${r.rtl ? "15.5pt" : "12pt"}; line-height: ${r.rtl ? 1.75 : 1.6}; direction: ${r.rtl ? "rtl" : "ltr"}; -webkit-print-color-adjust: exact; }
  h1, h2, .uni, .title { font-family: ${r.rtl ? `"Amiri", serif` : body}; color: #${NAVY}; }
  h1 { text-align: center; font-size: ${r.rtl ? "21pt" : "17pt"}; margin: 0 0 18pt; page-break-before: always; break-after: avoid; }
  h1.first { page-break-before: auto; }
  h2 { font-size: ${r.rtl ? "17pt" : "13.5pt"}; margin: 16pt 0 6pt; break-after: avoid; }
  p { text-align: justify; text-indent: 1cm; margin: 0 0 8pt; orphans: 3; widows: 3; }
  .refs p { text-indent: -1cm; padding-${r.rtl ? "right" : "left"}: 1cm; text-align: start; font-size: ${r.rtl ? "14pt" : "11pt"}; }
  .toc div { margin: 3pt 0; }
  .toc .c { font-weight: 700; color: #${NAVY}; margin-top: 7pt; }
  .toc .s { padding-${r.rtl ? "right" : "left"}: 1cm; }
  .cover { height: 24.6cm; display: flex; flex-direction: column; align-items: center; justify-content: space-between; text-align: center; padding: 0.4cm 0; }
  .cover img { max-height: 3.2cm; max-width: 8cm; object-fit: contain; margin-bottom: 8pt; }
  .uni { font-size: ${r.rtl ? "19pt" : "16pt"}; font-weight: 700; }
  .muted { color: #${GREY}; }
  .title { font-size: ${r.rtl ? "27pt" : "22pt"}; font-weight: 700; line-height: 1.45; border-top: 1.5pt solid #${NAVY}; border-bottom: 1.5pt solid #${NAVY}; padding: 14pt 6pt; margin: 6pt 0; max-width: 15cm; }
  .who { font-size: ${r.rtl ? "16pt" : "13pt"}; line-height: 2; }`;
}

function coverHtml(r) {
  return `<!doctype html><html lang="${r.lang}" dir="${r.rtl ? "rtl" : "ltr"}"><head><meta charset="utf-8"><style>${pdfCss(r)}</style></head><body>
  <div class="cover">
    <div>${r.logo ? `<img src="data:image/png;base64,${r.logo.data.toString("base64")}" alt="">` : ""}
      <div class="uni">${esc(r.university)}</div>${r.department ? `<div class="muted">${esc(r.L.dept)}: ${esc(r.department)}</div>` : ""}</div>
    <div><div class="muted">${esc(r.L.report)}</div><div class="title">${esc(r.title)}</div></div>
    <div class="who"><div>${esc(r.L.by)}: ${esc(r.student)}</div>${r.supervisor ? `<div>${esc(r.L.sup)}: ${esc(r.supervisor)}</div>` : ""}</div>
    <div class="muted">${esc(r.L.year)}: ${academicYear()}</div>
  </div></body></html>`;
}

function bodyHtml(r) {
  const P = (arr) => (arr || []).map((t) => `<p>${esc(t)}</p>`).join("");
  let toc = `<div class="c">${esc(r.L.intro)}</div>`;
  let main = `<h1>${esc(r.L.intro)}</h1>${P(r.intro)}`;
  r.chapters.forEach((c, ci) => {
    toc += `<div class="c">${esc(chapterLabel(r, ci))}: ${esc(c.title)}</div>` + c.sections.map((s, si) => `<div class="s">${secNum(ci, si)}&nbsp;&nbsp;${esc(s.title)}</div>`).join("");
    main += `<h1>${esc(chapterLabel(r, ci))}: ${esc(c.title)}</h1>` + c.sections.map((s, si) => `<h2>${secNum(ci, si)} ${esc(s.title)}</h2>${P(s.paragraphs)}`).join("");
  });
  toc += `<div class="c">${esc(r.L.conclusion)}</div><div class="c">${esc(r.L.refs)}</div>`;
  main += `<h1>${esc(r.L.conclusion)}</h1>${P(r.conclusion)}<h1>${esc(r.L.refs)}</h1><div class="refs">${P(r.references)}</div>`;
  return `<!doctype html><html lang="${r.lang}" dir="${r.rtl ? "rtl" : "ltr"}"><head><meta charset="utf-8"><style>${pdfCss(r)}</style></head><body>
  <h1 class="first">${esc(r.L.toc)}</h1><div class="toc">${toc}</div>${main}</body></html>`;
}

export async function buildPdf(r) {
  const chromium = (await import("@sparticuz/chromium")).default;
  const puppeteer = (await import("puppeteer-core")).default;
  const browser = await puppeteer.launch({
    args: chromium.args,
    executablePath: await chromium.executablePath(),
    headless: true,
  });
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
    const out = await PDFDocument.create();
    for (const src of [coverPdf, bodyPdf]) {
      const doc = await PDFDocument.load(src);
      (await out.copyPages(doc, doc.getPageIndices())).forEach((p) => out.addPage(p));
    }
    out.setTitle(r.title);
    out.setAuthor(r.student);
    return Buffer.from(await out.save());
  } finally {
    await browser.close();
  }
}

/* -------------------------------- PPTX ------------------------------ */
export async function buildPptx(r) {
  const pptx = new PptxGenJS();
  pptx.layout = "LAYOUT_WIDE"; // 13.33 x 7.5 in
  pptx.rtlMode = r.rtl;
  pptx.title = r.title;
  pptx.author = r.student;
  const font = r.rtl ? "Traditional Arabic" : "Georgia";
  const align = r.rtl ? "right" : "left";
  const base = { fontFace: font, color: INK, rtlMode: r.rtl };

  pptx.defineSlideMaster({
    title: "BODY", background: { color: "FFFFFF" },
    objects: [
      { rect: { x: 0, y: 0, w: 13.33, h: 0.12, fill: { color: NAVY } } },
      { line: { x: 0.7, y: 1.35, w: 11.93, h: 0, line: { color: "C9CEDA", width: 1 } } },
    ],
    slideNumber: { x: 6.4, y: 7.0, w: 0.6, h: 0.3, fontSize: 10, color: GREY, align: "center" },
  });

  // Title slide
  const t = pptx.addSlide();
  t.background = { color: "FFFFFF" };
  t.addShape(pptx.ShapeType.rect, { x: 0, y: 0, w: 13.33, h: 0.18, fill: { color: NAVY } });
  t.addShape(pptx.ShapeType.rect, { x: 0, y: 7.32, w: 13.33, h: 0.18, fill: { color: NAVY } });
  if (r.logo) {
    const h = 1.1, w = Math.min(3, (r.logo.width / r.logo.height) * h);
    t.addImage({ data: `data:image/png;base64,${r.logo.data.toString("base64")}`, x: (13.33 - w) / 2, y: 0.5, w, h });
  }
  t.addText([{ text: r.university, options: { bold: true, breakLine: true } }, { text: r.department ? `${r.L.dept}: ${r.department}` : "", options: { color: GREY, fontSize: 16 } }],
    { ...base, x: 0.8, y: 1.7, w: 11.73, h: 0.9, fontSize: 20, align: "center", color: NAVY });
  t.addText(r.title, { ...base, x: 1, y: 2.75, w: 11.33, h: 1.7, fontSize: 36, bold: true, color: NAVY, align: "center", valign: "middle" });
  t.addShape(pptx.ShapeType.line, { x: 4.67, y: 4.6, w: 4, h: 0, line: { color: NAVY, width: 1.5 } });
  t.addText([
    { text: `${r.L.by}: ${r.student}`, options: { breakLine: true } },
    ...(r.supervisor ? [{ text: `${r.L.sup}: ${r.supervisor}`, options: { breakLine: true } }] : []),
    { text: `${r.L.year}: ${academicYear()}`, options: { color: GREY, fontSize: 14 } },
  ], { ...base, x: 1, y: 4.8, w: 11.33, h: 1.6, fontSize: 18, align: "center" });

  const content = (title, bullets) => {
    const s = pptx.addSlide({ masterName: "BODY" });
    s.addText(title, { ...base, x: 0.7, y: 0.35, w: 11.93, h: 0.9, fontSize: 28, bold: true, color: NAVY, align, valign: "middle" });
    s.addText(bullets.map((b) => ({ text: b, options: { bullet: { indent: 18 }, breakLine: true, paraSpaceAfter: 10 } })),
      { ...base, x: 0.8, y: 1.6, w: 11.73, h: 5.2, fontSize: 20, align, valign: "top", lineSpacingMultiple: 1.1 });
  };
  const toc = [r.L.intro, ...r.chapters.map((c, i) => `${chapterLabel(r, i)}: ${c.title}`), r.L.conclusion, r.L.refs];
  content(r.L.toc, toc);
  content(r.L.intro, r.intro.slice(0, 5));
  r.chapters.forEach((c, ci) => {
    const d = pptx.addSlide();
    d.background = { color: NAVY };
    d.addText([{ text: chapterLabel(r, ci), options: { fontSize: 20, color: "C9CEDA", breakLine: true } }, { text: c.title, options: { fontSize: 34, bold: true, color: "FFFFFF" } }],
      { ...base, x: 1, y: 2.4, w: 11.33, h: 2.6, align: "center", valign: "middle" });
    c.sections.forEach((s, si) => content(`${secNum(ci, si)} ${s.title}`, (s.bullets || []).slice(0, 5)));
  });
  content(r.L.conclusion, r.conclusion.slice(0, 5));
  const refs = pptx.addSlide({ masterName: "BODY" });
  refs.addText(r.L.refs, { ...base, x: 0.7, y: 0.35, w: 11.93, h: 0.9, fontSize: 28, bold: true, color: NAVY, align });
  refs.addText(r.references.slice(0, 10).map((x) => ({ text: x, options: { breakLine: true, paraSpaceAfter: 6 } })),
    { ...base, rtlMode: false, x: 0.8, y: 1.55, w: 11.73, h: 5.3, fontSize: 13, align: "left", valign: "top", fontFace: "Georgia" });
  return Buffer.from(await pptx.write({ outputType: "nodebuffer" }));
}

/* -------------------------------- XLSX ------------------------------ */
export async function buildXlsx(r) {
  const wb = new ExcelJS.Workbook();
  wb.creator = r.student;
  wb.title = r.title;
  const font = r.rtl ? "Traditional Arabic" : "Times New Roman";
  const ws = wb.addWorksheet(r.L.report.slice(0, 28) || "Report", { views: [{ rightToLeft: r.rtl, state: "frozen", ySplit: 9 }], pageSetup: { paperSize: 9, orientation: "portrait", fitToPage: true, fitToWidth: 1, fitToHeight: 0, margins: { left: 0.98, right: 0.98, top: 0.98, bottom: 0.98, header: 0.3, footer: 0.3 } } });
  ws.columns = [{ width: 8 }, { width: 34 }, { width: 110 }];
  const navyFill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF" + NAVY } };
  const wrap = { wrapText: true, vertical: "top", horizontal: r.rtl ? "right" : "left", readingOrder: r.rtl ? "rtl" : "ltr" };
  const add = (vals, style = {}) => {
    const row = ws.addRow(vals);
    row.eachCell((c) => { c.font = { name: font, size: style.size || 14, bold: style.bold, color: { argb: style.color || "FF111111" } }; c.alignment = wrap; if (style.fill) c.fill = style.fill; });
    return row;
  };
  let row = add(["", r.university, ""], { bold: true, size: 18, color: "FF" + NAVY }); ws.mergeCells(row.number, 2, row.number, 3);
  if (r.department) { row = add(["", `${r.L.dept}: ${r.department}`, ""], { color: "FF" + GREY }); ws.mergeCells(row.number, 2, row.number, 3); } else add([]);
  row = add(["", r.title, ""], { bold: true, size: 22, color: "FF" + NAVY }); ws.mergeCells(row.number, 2, row.number, 3); row.height = 40;
  row = add(["", `${r.L.by}: ${r.student}`, ""]); ws.mergeCells(row.number, 2, row.number, 3);
  row = add(["", r.supervisor ? `${r.L.sup}: ${r.supervisor}` : "", ""]); ws.mergeCells(row.number, 2, row.number, 3);
  row = add(["", `${r.L.year}: ${academicYear()}`, ""], { color: "FF" + GREY }); ws.mergeCells(row.number, 2, row.number, 3);
  add([]);
  const head = add(["#", r.lang === "ar" ? "العنوان" : "Heading", r.lang === "ar" ? "النص" : "Text"], { bold: true, color: "FFFFFFFF", fill: navyFill });
  head.height = 24;
  const estHeight = (t) => Math.min(409, Math.max(22, Math.ceil(String(t).length / 95) * 21));
  const block = (num, heading, paras) => paras.forEach((t, i) => { const rw = add([i ? "" : num, i ? "" : heading, t]); rw.height = estHeight(t); rw.getCell(2).font = { name: font, size: 14, bold: true, color: { argb: "FF" + NAVY } }; });
  block("—", r.L.intro, r.intro);
  r.chapters.forEach((c, ci) => {
    const ch = add([String(ci + 1), `${chapterLabel(r, ci)}: ${c.title}`, ""], { bold: true, size: 15, color: "FF" + NAVY, fill: { type: "pattern", pattern: "solid", fgColor: { argb: "FFE8EBF2" } } });
    ws.mergeCells(ch.number, 2, ch.number, 3);
    c.sections.forEach((s, si) => block(secNum(ci, si), s.title, s.paragraphs || []));
  });
  block("—", r.L.conclusion, r.conclusion);

  const rs = wb.addWorksheet(r.L.refs.slice(0, 28), { views: [{ rightToLeft: false }] });
  rs.columns = [{ width: 6 }, { width: 140 }];
  rs.addRow(["#", r.L.refs]).eachCell((c) => { c.font = { name: font, bold: true, color: { argb: "FFFFFFFF" } }; c.fill = navyFill; });
  r.references.forEach((x, i) => { const rw = rs.addRow([i + 1, x]); rw.getCell(2).alignment = { wrapText: true, vertical: "top" }; rw.height = estHeight(x); });
  return Buffer.from(await wb.xlsx.writeBuffer());
}
