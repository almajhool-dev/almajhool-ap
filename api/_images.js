// Illustrative images from Wikimedia Commons (freely licensed), one per chapter, with author/licence credit.
import sharp from "sharp";

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

/** Finds one image per query (English keywords). Returns an array aligned with queries (null where none fits). */
export async function findImages(queries) {
  const used = new Set();
  return Promise.all(queries.map(async (q) => {
    if (!q) return null;
    for (const query of [q, q.split(/\s+/).slice(0, 2).join(" ")]) {
      const cands = (await search(query)).filter((c) => !used.has(c.url));
      for (const c of cands.slice(0, 3)) {
        used.add(c.url);
        const img = await download(c);
        if (img) return img;
      }
    }
    return null;
  }));
}
