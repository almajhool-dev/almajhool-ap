// The student's own source file (a full handout / ملزمة, lecture notes or a topic file): we split it into
// passages, build a digest for planning the outline, and retrieve the most relevant passages for each section
// so the report is written from that material and uses its terminology.

const AR_STOP = new Set("في من على إلى الى عن مع هذا هذه ذلك تلك التي الذي الذين هو هي هم كان كانت يكون تكون أن ان إن او أو ثم كما لقد قد لا لم لن ما ماذا كل بعض عند بين حيث حتى اي أي وهو وهي وفي ومن وعلى".split(" "));
const EN_STOP = new Set("the of and to in a an is are was were be been for on with as by at from that this these those it its or not can which into also has have had their there than then".split(" "));

export function normalizeArabic(s) {
  return String(s || "").replace(/[ً-ٰٟـ]/g, "").replace(/[أإآٱ]/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه");
}

/** Light stemming so «التعليم», «والتعليم», «بالتعليم» all match «تعليم». */
function tokens(text) {
  return normalizeArabic(text).toLowerCase().split(/[^\p{L}\p{N}]+/u).map((w) => {
    if (/\p{Script=Arabic}/u.test(w)) w = w.replace(/^(وال|بال|كال|فال|لل|ال|و|ب|ل|ف)(?=\p{L}{3,})/u, "").replace(/(ات|ون|ين|ها|هم|ه)$/u, (m) => (w.length - m.length >= 3 ? "" : m));
    return w;
  }).filter((w) => w.length >= 3 && !AR_STOP.has(w) && !EN_STOP.has(w));
}

export function cleanSource(raw, max = 150_000) {
  return String(raw || "")
    .normalize("NFC")
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F‪-‮⁦-⁩]/g, " ")
    .replace(/[<>{}`\\]/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
    .slice(0, max);
}

/** Splits into ~1100-character passages on paragraph boundaries and indexes them. */
export function prepareSource(text) {
  if (!text || text.length < 200) return null;
  const paras = text.split(/\n+/).map((p) => p.trim()).filter(Boolean);
  const chunks = [];
  let cur = "";
  for (const p of paras) {
    if (cur && cur.length + p.length > 1100) { chunks.push(cur); cur = ""; }
    cur += (cur ? "\n" : "") + p;
  }
  if (cur) chunks.push(cur);
  const index = chunks.map((c) => {
    const tf = new Map();
    for (const t of tokens(c)) tf.set(t, (tf.get(t) || 0) + 1);
    return tf;
  });
  const df = new Map();
  for (const tf of index) for (const t of tf.keys()) df.set(t, (df.get(t) || 0) + 1);
  // Frequent distinctive terms of the file (its vocabulary), for the outline prompt.
  const totals = new Map();
  for (const tf of index) for (const [t, n] of tf) totals.set(t, (totals.get(t) || 0) + n);
  const terms = [...totals].filter(([t]) => (df.get(t) || 0) <= Math.max(2, chunks.length * 0.6))
    .sort((a, b) => b[1] - a[1]).slice(0, 40).map(([t]) => t);
  // Heading-like short lines give the file's own structure.
  const headings = paras.filter((p) => p.split(/\s+/).length <= 9 && p.length >= 4 && !/[.،,؛:]$/.test(p)).slice(0, 60);
  return { text, chunks, index, df, terms, headings };
}

/** Digest for planning: the file's headings plus evenly spaced passages, within a character budget. */
export function digest(src, budget = 14_000) {
  if (src.text.length <= budget) return src.text;
  const head = src.headings.join(" | ").slice(0, 2500);
  const room = budget - head.length - 200;
  const per = 900;
  const n = Math.max(3, Math.floor(room / per));
  const step = src.chunks.length / n;
  const picks = [];
  for (let i = 0; i < n && Math.floor(i * step) < src.chunks.length; i++) picks.push(src.chunks[Math.floor(i * step)].slice(0, per));
  return `Headings found in the file: ${head}\n\nExcerpts across the file:\n${picks.join("\n---\n")}`;
}

/** Top passages for a query (BM25-style scoring), returned in their original order. */
export function retrieve(src, query, budget = 4200) {
  if (!src) return "";
  const q = [...new Set(tokens(query))];
  const N = src.chunks.length;
  const avg = src.chunks.reduce((n, c) => n + c.length, 0) / N;
  const scored = src.index.map((tf, i) => {
    let s = 0;
    for (const t of q) {
      const f = tf.get(t);
      if (!f) continue;
      const idf = Math.log(1 + (N - (src.df.get(t) || 0) + 0.5) / ((src.df.get(t) || 0) + 0.5));
      s += idf * (f * 2.2) / (f + 1.2 * (0.25 + 0.75 * src.chunks[i].length / avg));
    }
    return [i, s];
  }).filter(([, s]) => s > 0).sort((a, b) => b[1] - a[1]);
  const chosen = [];
  let used = 0;
  const parts = new Map();
  for (const [i] of scored) {
    const room = budget - used;
    if (room < 300) break;
    const piece = src.chunks[i].length <= room ? src.chunks[i] : src.chunks[i].slice(0, room);
    if (piece !== src.chunks[i] && chosen.length) continue;
    chosen.push(i); parts.set(i, piece); used += piece.length;
    if (used > budget * 0.85) break;
  }
  return chosen.sort((a, b) => a - b).map((i) => parts.get(i)).join("\n---\n");
}
