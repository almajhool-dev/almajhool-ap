// Shared server helpers. Files starting with _ are not exposed as routes.
import { neon } from "@neondatabase/serverless";
import { handleAuthProxyRequest } from "@neondatabase/auth/server";

export const sql = neon(process.env.DATABASE_URL);

const AUTH_BASE = process.env.NEON_AUTH_BASE_URL;
const COOKIE_SECRET = process.env.NEON_AUTH_COOKIE_SECRET;

export function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers },
  });
}

export class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export function route(fn) {
  return async (request) => {
    try {
      return await fn(request);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status);
      console.error(e);
      return json({ error: "حدث خطأ غير متوقع في الخادم، حاول مرة أخرى." }, 500);
    }
  };
}

/** Proxies sign-in through our own domain: first-party HttpOnly + Secure + SameSite=Strict cookies. */
export function authProxy(request, path) {
  return handleAuthProxyRequest({ request, path, baseUrl: AUTH_BASE, cookieSecret: COOKIE_SECRET, sameSite: "strict" });
}

export async function getUser(request) {
  const cookie = request.headers.get("cookie") || "";
  if (!cookie.includes("neon-auth")) return null;
  const headers = new Headers(request.headers);
  headers.delete("content-length");
  headers.delete("content-type");
  const url = new URL("/api/auth/get-session", request.url);
  const res = await authProxy(new Request(url, { method: "GET", headers }), "get-session");
  if (!res.ok) return null;
  const data = await res.json().catch(() => null);
  const u = data?.user;
  if (!u?.id) return null;
  const rows = await sql`
    INSERT INTO app_users (id, email, name, image) VALUES (${u.id}, ${u.email}, ${u.name}, ${u.image})
    ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email, name = EXCLUDED.name, image = EXCLUDED.image, last_seen = now()
    RETURNING id, email, name, image`;
  return rows[0];
}

export async function requireUser(request) {
  const user = await getUser(request);
  if (!user) throw new HttpError(401, "سجّل الدخول أولًا");
  return user;
}

export function clientIp(request) {
  return (request.headers.get("x-real-ip") || request.headers.get("x-forwarded-for") || "0").split(",")[0].trim();
}

/** Sliding-window rate limit stored in Postgres (works across all serverless instances). */
export async function rateLimit(key, max, windowSec, message) {
  const [r] = await sql`SELECT count(*)::int AS n FROM rate_hits WHERE key = ${key} AND at > now() - make_interval(secs => ${windowSec})`;
  if (r.n >= max) throw new HttpError(429, message || "طلبات كثيرة جدًا، انتظر قليلًا ثم حاول مجددًا.");
  await sql`INSERT INTO rate_hits (key) VALUES (${key})`;
  if (Math.random() < 0.05) await sql`DELETE FROM rate_hits WHERE at < now() - interval '2 days'`;
}

/** Same-origin check for state-changing requests (CSRF defence on top of SameSite=Strict). */
export function requireSameOrigin(request) {
  const origin = request.headers.get("origin");
  const host = request.headers.get("host");
  if (!origin || !host || new URL(origin).host !== host) throw new HttpError(403, "طلب غير مسموح");
}
