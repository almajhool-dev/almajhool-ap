// /api/style — sample reports the "advanced" mode learns from (saved per user, reusable).
//   GET            → list saved style profiles
//   POST {name, files:[base64]} → analyse 1–3 samples and save as one profile
//   DELETE ?id=    → remove a profile
import { route, json, requireUser, requireSameOrigin, rateLimit, HttpError, sql } from "./_lib.js";
import { analyzeSamples, describe } from "./_style.js";

let ready = false;
export async function ensureTable() {
  if (ready) return;
  await sql`CREATE TABLE IF NOT EXISTS style_profiles (
    id serial PRIMARY KEY, user_id text NOT NULL, name text NOT NULL, profile jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now())`;
  await sql`CREATE INDEX IF NOT EXISTS style_profiles_user ON style_profiles (user_id)`;
  ready = true;
}

export const GET = route(async (request) => {
  const user = await requireUser(request);
  await ensureTable();
  const rows = await sql`SELECT id, name, profile, created_at FROM style_profiles WHERE user_id = ${user.id} ORDER BY created_at DESC LIMIT 20`;
  return json({ profiles: rows.map((r) => ({ id: r.id, name: r.name, summary: describe(r.profile), created_at: r.created_at })) });
});

export const POST = route(async (request) => {
  requireSameOrigin(request);
  if (Number(request.headers.get("content-length") || 0) > 4_400_000) throw new HttpError(413, "حجم النماذج كبير جدًا (الحد 3 ميغابايت للمجموع)");
  const user = await requireUser(request);
  await rateLimit(`style:${user.id}`, 15, 3600, "رفعت نماذج كثيرة خلال ساعة، حاول لاحقًا.");
  const body = await request.json().catch(() => { throw new HttpError(400, "بيانات غير صالحة"); });
  const files = (Array.isArray(body.files) ? body.files : []).slice(0, 3)
    .map((b64) => Buffer.from(String(b64).replace(/^data:[^,]*,/, ""), "base64"));
  if (!files.length) throw new HttpError(400, "اختر ملف نموذج واحدًا على الأقل");
  if (files.some((f) => f.length < 200)) throw new HttpError(400, "أحد الملفات فارغ");
  const name = String(body.name || "").replace(/[<>{}`\\\u0000-\u001F]/g, "").trim().slice(0, 80) || "نموذجي";
  const profile = await analyzeSamples(files);
  await ensureTable();
  const n = await sql`SELECT count(*)::int AS n FROM style_profiles WHERE user_id = ${user.id}`;
  if (n[0].n >= 20) await sql`DELETE FROM style_profiles WHERE id IN (SELECT id FROM style_profiles WHERE user_id = ${user.id} ORDER BY created_at ASC LIMIT 1)`;
  const [row] = await sql`INSERT INTO style_profiles (user_id, name, profile) VALUES (${user.id}, ${name}, ${JSON.stringify(profile)}::jsonb) RETURNING id, created_at`;
  return json({ id: row.id, name, summary: describe(profile), created_at: row.created_at });
});

export const DELETE = route(async (request) => {
  requireSameOrigin(request);
  const user = await requireUser(request);
  const id = Number(new URL(request.url).searchParams.get("id"));
  if (!Number.isInteger(id)) throw new HttpError(400, "معرّف غير صالح");
  await ensureTable();
  await sql`DELETE FROM style_profiles WHERE id = ${id} AND user_id = ${user.id}`;
  return json({ ok: true });
});
