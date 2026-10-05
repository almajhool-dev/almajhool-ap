// Learns a house style from sample reports (DOCX / PDF / TXT): structure, heading conventions,
// paragraph rhythm, and — for Word files — the page formatting (margins, font, size, line spacing).
import JSZip from "jszip";
import mammoth from "mammoth";
import { HttpError } from "./_lib.js";

const AR = /\p{Script=Arabic}/u;
const decode = (s) => s.replace(/<[^>]+>/g, "").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/\s+/g, " ").trim();
const words = (s) => s.split(/\s+/).filter(Boolean).length;
const HEADING_HINT = /^(الفصل|المبحث|المطلب|المحور|الباب|أولاً|أولا|ثانياً|ثانيا|ثالثاً|رابعاً|خامساً|المقدمة|الخاتمة|التوصيات|الاستنتاجات|المصادر|المراجع|Chapter|Section|Introduction|Conclusion|References|Abstract|\d+(\.\d+)*[.)\-\s])/i;

function mostCommon(map) { let best = null, n = 0; for (const [k, v] of map) if (v > n) { best = k; n = v; } return best; }
function count(map, k, w = 1) { if (k != null) map.set(k, (map.get(k) || 0) + w); }

async function docxFormat(buf) {
  const zip = await JSZip.loadAsync(buf);
  const doc = (await zip.file("word/document.xml")?.async("string")) || "";
  const styles = (await zip.file("word/styles.xml")?.async("string")) || "";
  const fmt = {};
  const mar = doc.match(/<w:pgMar\b[^>]*>/);
  if (mar) {
    const g = (a) => Number((mar[0].match(new RegExp(`w:${a}="(-?\\d+)"`)) || [])[1]);
    const cm = (t) => (Number.isFinite(t) && t > 0 ? Math.round((t / 567) * 10) / 10 : null);
    fmt.marginsCm = { top: cm(g("top")), bottom: cm(g("bottom")), left: cm(g("left")), right: cm(g("right")) };
  }
  const fonts = new Map(), sizes = new Map(), lines = new Map(), jc = new Map();
  for (const m of doc.matchAll(/<w:r>([\s\S]*?)<\/w:r>|<w:r [^>]*>([\s\S]*?)<\/w:r>/g)) {
    const r = m[1] || m[2] || "";
    const text = (r.match(/<w:t[^>]*>([^<]*)<\/w:t>/g) || []).join("").length;
    if (!text) continue;
    const f = r.match(/w:rFonts[^>]*w:cs="([^"]+)"/) || r.match(/w:rFonts[^>]*w:ascii="([^"]+)"/);
    count(fonts, f?.[1], text);
    const sz = r.match(/<w:szCs w:val="(\d+)"/) || r.match(/<w:sz w:val="(\d+)"/);
    count(sizes, sz ? Number(sz[1]) / 2 : null, text);
  }
  for (const m of doc.matchAll(/<w:spacing\b[^>]*w:line="(\d+)"[^>]*\/>/g)) if (!/lineRule="(exact|atLeast)"/.test(m[0])) count(lines, Math.round((Number(m[1]) / 240) * 100) / 100);
  for (const para of doc.split("</w:p>")) {
    const len = (para.match(/<w:t[^>]*>([^<]*)<\/w:t>/g) || []).join("").length;
    const j = para.match(/<w:pPr>[\s\S]*?<w:jc w:val="(\w+)"/);
    if (len > 200) count(jc, j ? j[1] : "start", len);
  }
  const defFont = styles.match(/<w:rPrDefault>[\s\S]*?w:rFonts[^>]*w:cs="([^"]+)"/)?.[1] || styles.match(/<w:rPrDefault>[\s\S]*?w:rFonts[^>]*w:ascii="([^"]+)"/)?.[1];
  const defSize = styles.match(/<w:rPrDefault>[\s\S]*?<w:szCs w:val="(\d+)"/)?.[1] || styles.match(/<w:rPrDefault>[\s\S]*?<w:sz w:val="(\d+)"/)?.[1];
  fmt.font = mostCommon(fonts) || defFont || null;
  fmt.sizePt = mostCommon(sizes) || (defSize ? Number(defSize) / 2 : null);
  fmt.lineSpacing = mostCommon(lines);
  const a = mostCommon(jc);
  fmt.align = a === "both" || a === "distribute" ? "justify" : a || null;
  if (fmt.font && !/^[\p{L}\p{N} ()\-.]{2,40}$/u.test(fmt.font)) fmt.font = null;
  if (fmt.sizePt && (fmt.sizePt < 9 || fmt.sizePt > 22)) fmt.sizePt = null;
  if (fmt.lineSpacing && (fmt.lineSpacing < 0.9 || fmt.lineSpacing > 2.6)) fmt.lineSpacing = null;
  return fmt;
}

async function docxStructure(buf) {
  const { value: html } = await mammoth.convertToHtml({ buffer: buf });
  const blocks = [...html.matchAll(/<(h[1-4]|p)>([\s\S]*?)<\/\1>/g)].map((m) => {
    const raw = m[2];
    const text = decode(raw);
    const strongOnly = /^<strong>[\s\S]*<\/strong>$/.test(raw.trim());
    const isHeading = m[1].startsWith("h") || (strongOnly && words(text) <= 14) || (words(text) <= 10 && HEADING_HINT.test(text) && !/[.:؛]$/.test(text));
    return { text, isHeading };
  }).filter((b) => b.text);
  return blocks;
}

/** Plain text / PDF: wrapped lines are re-joined into paragraphs; short heading-like lines stay separate. */
function textStructure(text) {
  const out = [];
  let buf = [];
  const flush = () => { if (buf.length) { out.push({ text: buf.join(" "), isHeading: false }); buf = []; } };
  for (const raw of text.split(/\n/)) {
    const t = raw.replace(/\s+/g, " ").trim();
    if (!t) { flush(); continue; }
    if (/^\d{1,3}$/.test(t)) continue; // page numbers
    if (words(t) <= 10 && HEADING_HINT.test(t) && !/[.؛،,]$/.test(t)) { flush(); out.push({ text: t, isHeading: true }); continue; }
    buf.push(t);
    if (/[.!?؟]["»)]?$/.test(t)) flush();
  }
  flush();
  return out;
}

async function pdfText(buf) {
  const { extractText, getDocumentProxy } = await import("unpdf");
  const pdf = await getDocumentProxy(new Uint8Array(buf));
  const { text } = await extractText(pdf, { mergePages: false });
  return fixArabicOrder((Array.isArray(text) ? text : [text]).join("\n"));
}

/**
 * Some PDFs (e.g. those printed from browsers) store Arabic lines in visual order: words reversed and
 * sentence punctuation glued to the front of the first word. Detect that across the document and restore
 * logical order so headings and the style excerpt read correctly.
 */
export function fixArabicOrder(text) {
  const lines = text.split("\n");
  const arabicLine = (l) => (l.match(/\p{Script=Arabic}/gu) || []).length > l.replace(/\s/g, "").length * 0.6;
  let front = 0, back = 0;
  for (const l of lines) {
    if (!arabicLine(l)) continue;
    const t = l.trim();
    if (/^[.،؛:!؟]\p{Script=Arabic}/u.test(t)) front++;
    if (/\p{Script=Arabic}[.،؛:!؟]$/u.test(t)) back++;
  }
  if (front <= back || front < 2) return text;
  return lines.map((l) => {
    if (!arabicLine(l)) return l;
    return l.trim().split(/\s+/).reverse()
      .map((w) => w.replace(/^([.،؛:!؟]+)(.+)$/u, "$2$1")).join(" ");
  }).join("\n");
}

/** Detects the file kind from magic bytes (never trusts the name). */
function kindOf(buf) {
  if (buf.subarray(0, 4).equals(Buffer.from([0x50, 0x4b, 0x03, 0x04]))) return "docx";
  if (buf.subarray(0, 5).toString() === "%PDF-") return "pdf";
  const s = buf.subarray(0, 2000).toString("utf8");
  if (!s.includes("\uFFFD") && !/[\u0000-\u0008]/.test(s)) return "txt";
  return null;
}

export async function analyzeSamples(files) {
  const all = [];
  let format = null;
  const kinds = [];
  for (const f of files) {
    const kind = kindOf(f);
    if (!kind) throw new HttpError(400, "صيغة النموذج غير مدعومة (Word أو PDF أو نص فقط)");
    kinds.push(kind);
    try {
      if (kind === "docx") {
        all.push(...(await docxStructure(f)));
        if (!format) format = await docxFormat(f);
      } else if (kind === "pdf") all.push(...textStructure(await pdfText(f)));
      else all.push(...textStructure(f.toString("utf8")));
    } catch (e) {
      if (e instanceof HttpError) throw e;
      throw new HttpError(400, "تعذّر قراءة أحد ملفات النموذج — تأكد أنه ملف Word أو PDF سليم وغير محمي بكلمة مرور");
    }
  }
  // Ignore the cover page: headings before the first real paragraph (except the last few, e.g. «المقدمة»).
  const firstPara = all.findIndex((b) => !b.isHeading && words(b.text) >= 25);
  const body = firstPara > 0 ? all.filter((b, i) => i >= firstPara - 2 || !b.isHeading) : all;
  const headings = body.filter((b) => b.isHeading).map((b) => b.text.slice(0, 120));
  const paras = body.filter((b) => !b.isHeading && words(b.text) >= 25).map((b) => b.text);
  if (paras.length < 2) throw new HttpError(400, "النموذج قصير جدًا أو نصّه غير قابل للقراءة (قد يكون PDF مصوّرًا)");
  const avgParaWords = Math.round(paras.reduce((n, p) => n + words(p), 0) / paras.length);
  const joined = headings.join(" ");
  const chapterWord = ["المبحث", "الفصل", "المحور", "الباب", "Chapter", "Section"]
    .map((w) => [w, (joined.match(new RegExp(`(^|\\s|\\|)${w}(?=\\s)`, "gu")) || []).length]).filter(([, n]) => n >= 2).sort((a, b) => b[1] - a[1])[0]?.[0] || null;
  const numbering = /(^|\s)(أولاً|أولا|ثانياً|ثانيا)/.test(joined) ? "ordinal-words" : /(^|\s)\d+\.\d+/.test(joined) ? "decimal" : null;
  // A few representative paragraphs from the middle of the document (tone/rhythm reference, never copied).
  const mid = Math.floor(paras.length / 2);
  const excerpt = paras.slice(Math.max(0, mid - 1), mid + 2).join("\n\n").slice(0, 1400);
  return {
    kinds, lang: AR.test(excerpt) ? "ar" : "en",
    headings: [...new Set(headings)].slice(0, 30), chapterWord, numbering,
    avgParaWords, paragraphs: paras.length, excerpt, format: format || {},
  };
}

/** Human summary in Arabic for the interface. */
export function describe(p) {
  const f = p.format || {};
  const parts = [`${p.headings.length} عنوانًا`, `${p.paragraphs} فقرة بمتوسط ${p.avgParaWords} كلمة`];
  if (p.chapterWord) parts.push(`التقسيم بـ«${p.chapterWord}»`);
  if (f.font) parts.push(`الخط ${f.font}${f.sizePt ? " " + f.sizePt : ""}`);
  if (f.marginsCm?.top) parts.push(`الهوامش ${f.marginsCm.top} سم`);
  if (f.lineSpacing) parts.push(`تباعد الأسطر ${f.lineSpacing}`);
  return parts.join(" · ");
}

/** Extra writing instructions derived from the profile. */
export function styleInstructions(p) {
  if (!p) return "";
  return `
House style learned from the student's own sample report(s) — follow it closely:
- structure and heading conventions like these examples: ${p.headings.slice(0, 14).join(" | ")}
- paragraphs of about ${p.avgParaWords} words each
- match the register, rhythm and connective phrases of this excerpt (style reference only; never copy its content or sentences):
"""${p.excerpt}"""`;
}
