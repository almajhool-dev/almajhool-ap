import { route, json, getUser, sql, rateLimit, clientIp } from "./_lib.js";

export const GET = route(async (request) => {
  await rateLimit(`me:${clientIp(request)}`, 300, 600);
  const user = await getUser(request);
  if (!user) return json({ user: null });
  const reports = await sql`SELECT id, title, lang, format, pages, created_at FROM reports WHERE user_id = ${user.id} ORDER BY created_at DESC LIMIT 20`;
  return json({ user, reports });
});
