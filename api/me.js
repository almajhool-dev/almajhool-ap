import { route, json, getUser, sql, rateLimit, clientIp } from "./_lib.js";

let ready = false;
export const GET = route(async (request) => {
  await rateLimit(`me:${clientIp(request)}`, 300, 600);
  const user = await getUser(request);
  if (!user) return json({ user: null });
  if (!ready) { await sql`ALTER TABLE reports ADD COLUMN IF NOT EXISTS file_url text, ADD COLUMN IF NOT EXISTS size integer`.catch(() => {}); ready = true; }
  const reports = await sql`SELECT id, title, lang, format, pages, created_at, file_url, size FROM reports WHERE user_id = ${user.id} ORDER BY created_at DESC LIMIT 20`;
  return json({ user, reports });
});
