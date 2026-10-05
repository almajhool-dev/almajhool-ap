// POST /api/generate → validates input, generates the report and returns the finished file.
import sharp from "sharp";
import { route, json, requireUser, requireSameOrigin, rateLimit, clientIp, HttpError, sql } from "./_lib.js";
import { setOidcToken } from "./_ai.js";
import { buildContent, LANGS } from "./_content.js";
import { buildDocx, buildPdf, buildPptx, buildXlsx } from "./_build.js";

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
    const img = sharp(buf, { limitInputPixels: 40_000_000, failOn: "error" }).rotate().resize({ width: 800, height: 800, fit: "inside", withoutEnlargement: true });
    const { data, info } = await img.png({ compressionLevel: 9 }).toBuffer({ resolveWithObject: true });
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

  const input = {
    title: clean(body.title, 220, { required: true, label: "عنوان التقرير" }),
    student: clean(body.student, 120, { required: true, label: "اسم الطالب" }),
    supervisor: clean(body.supervisor, 120, { label: "اسم المشرف" }),
    university: clean(body.university, 160, { required: true, label: "الجامعة أو المعهد" }),
    department: clean(body.department, 120, { label: "القسم" }),
    lang, format, pages,
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
  return new Response(file, {
    headers: {
      "Content-Type": FORMATS[format].mime,
      "Content-Disposition": `attachment; filename="report.${format}"; filename*=UTF-8''${encodeURIComponent(name)}`,
      "Cache-Control": "no-store",
      "X-Gen-Stats": JSON.stringify({ ms: report.stats.ms, fail: report.stats.fail.length, ok: report.stats.ok }).slice(0, 900),
    },
  });
});
