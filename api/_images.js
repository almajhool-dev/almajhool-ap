// Illustrative images from Wikimedia Commons (freely licensed), one per chapter, with author/licence credit.
import sharp from "sharp";
import { gatewayKey, pool } from "./_ai.js";

const UA = "AcademicReportEngine/2.0 (https://academic-report-engine.vercel.app; reports)";
const strip = (s) => String(s || "").replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();

async function getJson(url, ms = 12_000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try {
    const r = await fetch(url, { headers: { "User-Agent": UA }, signal: ctrl.signal });
    return r.ok ? await r.json() : null;
  } catch { return null; } finally { clearTimeout(t); }
}

async function search(query) {
  const url = "https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search&gsrnamespace=6&gsrlimit=12" +
    `&gsrsearch=${encodeURIComponent(query + " filetype:bitmap -logo -map -flag -icon")}` +
    "&prop=imageinfo&iiprop=url|size|mime|extmetadata&iiurlwidth=1000";
  const j = await getJson(url);
  const pages = Object.values(j?.query?.pages || {}).sort((a, b) => (a.index || 0) - (b.index || 0));
  return pages.map((p) => {
    const ii = p.imageinfo?.[0];
    if (!ii || !/image\/(jpeg|png)/.test(ii.mime) || ii.width < 640 || ii.height < 400) return null;
    const ratio = ii.width / ii.height;
    if (ratio < 1.0 || ratio > 2.2) return null; // landscape photos fit the page best
    const m = ii.extmetadata || {};
    const lic = strip(m.LicenseShortName?.value);
    if (!lic || /non-free|fair use/i.test(lic)) return null;
    return { url: ii.thumburl || ii.url, author: strip(m.Artist?.value).slice(0, 60), license: lic, title: p.title.replace(/^File:/, "") };
  }).filter(Boolean);
}

async function download(c) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 15_000);
  try {
    const r = await fetch(c.url, { headers: { "User-Agent": UA }, signal: ctrl.signal });
    if (!r.ok) return null;
    const buf = Buffer.from(await r.arrayBuffer());
    const { data, info } = await sharp(buf, { limitInputPixels: 60_000_000 }).rotate()
      .resize({ width: 1100, height: 700, fit: "inside", withoutEnlargement: true }).jpeg({ quality: 80, mozjpeg: true })
      .toBuffer({ resolveWithObject: true });
    return { data, width: info.width, height: info.height, credit: `${c.author ? c.author + " · " : ""}${c.license} · Wikimedia Commons` };
  } catch { return null; } finally { clearTimeout(t); }
}

const STOP = new Set(["with", "from", "and", "the", "for", "into", "over", "under", "between", "photo", "image", "view", "system", "process"]);
/** A Commons photo counts only if its file name mentions a meaningful word of the query (avoids off-topic pictures). */
function relevant(c, query) {
  const name = c.title.toLowerCase().replace(/[_\-.]/g, " ");
  return query.toLowerCase().split(/\s+/).filter((w) => w.length > 3 && !STOP.has(w)).some((w) => name.includes(w.replace(/s$/, "")));
}

async function commonsImage(query, used) {
  if (!query) return null;
  for (const q of [...new Set([query, query.split(/\s+/).slice(0, 2).join(" ")])]) {
    const cands = (await search(q)).filter((c) => !used.has(c.url) && relevant(c, query));
    for (const c of cands.slice(0, 3)) {
      used.add(c.url);
      const img = await download(c);
      if (img) return { ...img, kind: "photo" };
    }
  }
  return null;
}

const toJpeg = async (buf, cropBottom = 0) => {
  let img = sharp(buf, { limitInputPixels: 60_000_000 });
  if (cropBottom) { const m = await img.metadata(); img = img.extract({ left: 0, top: 0, width: m.width, height: Math.round(m.height * (1 - cropBottom)) }); }
  const { data, info } = await img.resize({ width: 1100, height: 700, fit: "inside", withoutEnlargement: true }).jpeg({ quality: 82, mozjpeg: true }).toBuffer({ resolveWithObject: true });
  return { data, width: info.width, height: info.height };
};

/** AI illustration through Vercel AI Gateway (Gemini image models). */
async function gatewayImage(prompt) {
  const key = gatewayKey();
  if (!key) return null;
  for (const model of ["google/gemini-3.1-flash-image-preview", "google/gemini-2.5-flash-image"]) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 60_000);
    try {
      const r = await fetch("https://ai-gateway.vercel.sh/v1/chat/completions", {
        method: "POST", signal: ctrl.signal,
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
        body: JSON.stringify({ model, modalities: ["image", "text"], stream: false, messages: [{ role: "user", content: prompt }] }),
      });
      if (!r.ok) { if (r.status === 401 || r.status === 403) return null; continue; }
      const j = await r.json();
      const url = j?.choices?.[0]?.message?.images?.[0]?.image_url?.url || "";
      const b64 = url.split(",")[1];
      if (b64) return { ...(await toJpeg(Buffer.from(b64, "base64"))), kind: "ai" };
    } catch { /* try next */ } finally { clearTimeout(t); }
  }
  return null;
}

/** Free keyless fallback generator (its corner watermark is cropped off). */
async function pollinationsImage(prompt, seed) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 45_000);
  try {
    const url = `https://image.pollinations.ai/prompt/${encodeURIComponent(prompt.slice(0, 600))}?width=1100&height=700&nologo=true&model=flux&seed=${seed}`;
    const r = await fetch(url, { headers: { "User-Agent": UA }, signal: ctrl.signal });
    if (!r.ok || !/^image\//.test(r.headers.get("content-type") || "")) return null;
    return { ...(await toJpeg(Buffer.from(await r.arrayBuffer()), 0.07)), kind: "ai" };
  } catch { return null; } finally { clearTimeout(t); }
}

export function illustrationPrompt({ topic, chapter, section, query }) {
  return `Create one high-quality, realistic illustration for an academic university report.
Report topic: "${topic}". Chapter: "${chapter}". Section: "${section}". Visual subject: ${query || section}.
Style: professional editorial photography or a clean scientific illustration, accurate to the subject, natural lighting, landscape 16:10.
Strictly no text, no letters, no numbers, no captions, no logos, no watermarks, no flags.`;
}

/**
 * One illustration per item ({query, prompt}): a relevant freely-licensed photo, otherwise an AI-generated
 * image. Returns an array aligned with items; null entries are filled later with drawn diagrams.
 */
export async function findSectionImages(items, { fallbacks = [] } = {}) {
  const used = new Set();
  return pool(items, 4, async (it, i) => {
    const photo = await commonsImage(it.query, used);
    if (photo) return photo;
    // The free generator only understands English: give it the English subject + topic keywords, or skip it.
    const en = [it.query, it.topicEn].filter((x) => x && /[a-z]{3}/i.test(x)).join(", ");
    const ai = (await gatewayImage(it.prompt)) ||
      (en ? await pollinationsImage(`Professional realistic editorial photograph of ${en}. Accurate, high detail, natural light, no text, no letters, no watermark`, 1000 + i) : null);
    if (ai) return { ...ai, credit: "AI" };
    for (const f of fallbacks) { const p = await commonsImage(f, used); if (p) return p; }
    return null;
  });
}

/** Kept for compatibility: one image per query with broader fallbacks. */
export async function findImages(queries, fallbacks = []) {
  return findSectionImages(queries.map((q) => ({ query: q, prompt: illustrationPrompt({ topic: q, chapter: q, section: q, query: q }) })), { fallbacks });
}
