// POST /api/generate → validates input, generates the report and returns the finished file.
import { route, json, requireUser, requireSameOrigin, rateLimit, clientIp, HttpError, sql } from "./_lib.js";
import { setOidcToken } from "./_ai.js";
import { buildContent, LANGS } from "./_content.js";
import { buildDocx, buildPdf, buildPptx, buildXlsx } from "./_build.js";
import { removeBackground } from "./_logo.js";
import { ensureTable } from "./style.js";

const PALETTES = { navy: "1B2A6B", burgundy: "6D1A2A", emerald: "0F6B4F", charcoal: "36454F" };
const BACKGROUNDS = { none: null, ivory: "FBF8F1", mist: "F4F7FB", sage: "F3F7F2" };
const TOPIC = { black: "000000", blue: "1F4E9A" };

const FORMATS = {
  docx: { build: buildDocx, mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document" },
  pdf: { build: buildPdf, mime: "application/pdf" },
  pptx: { build: buildPptx, mime: "application/vnd.openxmlformats-officedocument.presentationml.presentation" },
  xlsx: { build: buildXlsx, mime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" },
};

// Strip control chars, markup and anything that could break out of the document context.
function clean(v, max, { required = false, label = "" } = {}) {
  const s = String(v ?? "")
    .normalize("NFC")
    .replace(/[\u0000-\u001F\u007F\u202A-\u202E\u2066-\u2069]/g, " ")
    .replace(/[<>{}`\\]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  if (required && s.length < 2) throw new HttpError(400, `الحقل «${label}» مطلوب`);
  if (s.length > max) throw new HttpError(400, `الحقل «${label}» أطول من المسموح (${max} حرفًا)`);
  return s;
}

async function processLogo(b64) {
  if (!b64) return null;
  if (typeof b64 !== "string" || b64.length > 2_900_000) throw new HttpError(400, "حجم الصورة يجب أن يكون أقل من 2 ميغابايت");
  const buf = Buffer.from(b64.replace(/^data:[^,]*,/, ""), "base64");
  // Accept only real PNG / JPEG / WEBP by magic bytes, then fully re-encode (drops any embedded payload/metadata).
  const isPng = buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  const isJpg = buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
  const isWebp = buf.subarray(0, 4).toString() === "RIFF" && buf.subarray(8, 12).toString() === "WEBP";
  if (!isPng && !isJpg && !isWebp) throw new HttpError(400, "صيغة الصورة غير مدعومة (PNG أو JPG أو WEBP فقط)");
  try {
    // Re-encodes the image (drops any embedded payload/metadata), removes a plain background and trims it.
    const { data, info } = await removeBackground(buf);
    return { data, width: info.width, height: info.height };
  } catch {
    throw new HttpError(400, "تعذّر قراءة الصورة، جرّب صورة أخرى");
  }
}

export const POST = route(async (request) => {
  requireSameOrigin(request);
  const len = Number(request.headers.get("content-length") || 0);
  if (len > 3_500_000) throw new HttpError(413, "حجم الطلب كبير جدًا");
  const user = await requireUser(request);
  await rateLimit(`ip:${clientIp(request)}`, 20, 600);
  await rateLimit(`u:${user.id}:h`, 6, 3600, "وصلت للحد المسموح (6 تقارير بالساعة). حاول بعد قليل.");
  await rateLimit(`u:${user.id}:d`, 25, 86400, "وصلت للحد اليومي (25 تقريرًا). عُد غدًا.");

  const body = await request.json().catch(() => { throw new HttpError(400, "بيانات غير صالحة"); });
  const lang = String(body.lang || "ar");
  const format = String(body.format || "docx");
  if (!LANGS[lang]) throw new HttpError(400, "لغة غير مدعومة");
  if (!FORMATS[format]) throw new HttpError(400, "صيغة غير مدعومة");
  const pages = Math.round(Number(body.pages));
  if (!Number.isFinite(pages) || pages < 3 || pages > 40) throw new HttpError(400, "عدد الصفحات يجب أن يكون بين 3 و 40");

  const students = (Array.isArray(body.students) ? body.students : [body.student])
    .map((n, i) => clean(n, 80, { label: `اسم الطالب ${i + 1}` })).filter((n) => n.length >= 2).slice(0, 10);
  if (!students.length) throw new HttpError(400, "اكتب اسم طالب واحد على الأقل");
  const mode = body.mode === "advanced" ? "advanced" : "standard";
  const theme = mode === "advanced"
    ? { primary: PALETTES[body.palette] || PALETTES.navy, topic: TOPIC[body.topicColor] || TOPIC.blue,
        border: ["none", "cover", "all"].includes(body.border) ? body.border : "cover", bg: BACKGROUNDS[body.background] ?? null }
    : { primary: "000000", topic: TOPIC[body.topicColor] || TOPIC.black, border: "none", bg: null };

  let style = null;
  if (mode === "advanced" && body.styleId) {
    await ensureTable();
    const [row] = await sql`SELECT profile FROM style_profiles WHERE id = ${Number(body.styleId) || 0} AND user_id = ${user.id}`;
    if (!row) throw new HttpError(400, "النموذج المحفوظ غير موجود، اختر نموذجًا آخر");
    style = row.profile;
  }

  const input = {
    title: clean(body.title, 220, { required: true, label: "عنوان التقرير" }),
    students,
    supervisor: clean(body.supervisor, 120, { label: "اسم المشرف" }),
    university: clean(body.university, 160, { required: true, label: "الجامعة أو المعهد" }),
    college: clean(body.college, 160, { label: "الكلية" }),
    department: clean(body.department, 120, { label: "القسم" }),
    lang, format, pages, mode, theme, style,
    images: body.images !== false,
    fmt: style?.format || null,
  };
  const logo = await processLogo(body.logo);
  setOidcToken(request.headers.get("x-vercel-oidc-token"));

  let report;
  try {
    report = await buildContent(input);
  } catch (e) {
    console.error("content", e);
    return json({ error: "خدمة الكتابة مزدحمة الآن، حاول مرة أخرى بعد دقيقة.", detail: (e.details || [e.message]).slice(-6) }, 503);
  }
  report.logo = logo;
  const file = await FORMATS[format].build(report);
  await sql`INSERT INTO reports (user_id, title, lang, format, pages) VALUES (${user.id}, ${input.title}, ${lang}, ${format}, ${pages})`;

  const name = `${input.title.slice(0, 80)}.${format}`;
  report.style = undefined;
  return new Response(file, {
    headers: {
      "Content-Type": FORMATS[format].mime,
      "Content-Disposition": `attachment; filename="report.${format}"; filename*=UTF-8''${encodeURIComponent(name)}`,
      "Cache-Control": "no-store",
      "X-Gen-Stats": JSON.stringify({ ms: report.stats.ms, fail: report.stats.fail.length, refs: report.references.length, images: report.chapters.filter((c) => c.image).length }).slice(0, 900),
    },
  });
});
