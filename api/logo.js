// GET /api/logo?src=en|ar|commons&f=<file name>  → institution logo as transparent PNG (cached at the edge)
// GET /api/logo?q=<name>                           → live search on Arabic/English Wikipedia for logos not in the library
import sharp from "sharp";
import { route, json, HttpError, rateLimit, clientIp } from "./_lib.js";
import { removeBackground } from "./_logo.js";

const UA = "AcademicReportEngine/2.0 (https://academic-report-engine.vercel.app; reports)";
const HOST = { en: "en.wikipedia.org", ar: "ar.wikipedia.org", commons: "commons.wikimedia.org" };
const LOGO_RE = /(logo|شعار|seal|emblem|crest|insignia|badge|لوغو|لوكو|logotype)/i;

async function fetchT(url, ms = 12_000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try { return await fetch(url, { headers: { "User-Agent": UA }, signal: ctrl.signal, redirect: "follow" }); }
  finally { clearTimeout(t); }
}

async function search(q) {
  const out = [];
  for (const wiki of /\p{Script=Arabic}/u.test(q) ? ["ar", "en"] : ["en", "ar"]) {
    const url = `https://${HOST[wiki]}/w/api.php?action=query&format=json&generator=search&gsrlimit=8&gsrsearch=${encodeURIComponent(q)}` +
      "&prop=pageimages|pageprops&piprop=name&pilicense=any&ppprop=wikibase_item";
    const r = await fetchT(url).catch(() => null);
    if (!r?.ok) continue;
    const j = await r.json();
    for (const p of Object.values(j?.query?.pages || {}).sort((a, b) => a.index - b.index)) {
      const f = p.pageimage;
      if (!f || !(LOGO_RE.test(f) || /\.(svg|png)$/i.test(f))) continue;
      if (!/(جامع|كلي|معهد|أكاديمي|univers|college|institut|academ|polytechnic)/i.test(p.title)) continue;
      out.push({ id: p.pageprops?.wikibase_item || p.title, ar: wiki === "ar" ? p.title : "", en: wiki === "en" ? p.title : "", w: wiki, f });
    }
    if (out.length >= 4) break;
  }
  const seen = new Set();
  return out.filter((x) => !seen.has(x.id) && seen.add(x.id)).slice(0, 8);
}

export const GET = route(async (request) => {
  const url = new URL(request.url);
  const q = (url.searchParams.get("q") || "").trim();
  if (q) {
    if (q.length < 3 || q.length > 80) throw new HttpError(400, "اكتب اسمًا أوضح");
    await rateLimit(`logoq:${clientIp(request)}`, 40, 600);
    return json({ results: await search(q) }, 200, { "Cache-Control": "public, s-maxage=86400" });
  }
  const src = url.searchParams.get("src");
  const f = url.searchParams.get("f") || "";
  if (!HOST[src] || !f || f.length > 200 || /[\/\\?#]|\.\./.test(f)) throw new HttpError(400, "طلب غير صالح");
  const r = await fetchT(`https://${HOST[src]}/wiki/Special:FilePath/${encodeURIComponent(f)}?width=500`);
  if (!r.ok) throw new HttpError(404, "تعذّر جلب الشعار");
  const type = r.headers.get("content-type") || "";
  if (!/^image\/(png|jpeg|gif|webp|svg\+xml)/.test(type)) throw new HttpError(404, "الملف ليس صورة");
  let buf = Buffer.from(await r.arrayBuffer());
  if (/svg/.test(type)) buf = await sharp(buf, { density: 200 }).png().toBuffer();
  const { data } = await removeBackground(buf);
  return new Response(data, { headers: { "Content-Type": "image/png", "Cache-Control": "public, max-age=86400, s-maxage=2592000" } });
});
