// /api/auth/<path> → Neon Auth (rewritten in vercel.json to /api/auth?__p=<path>)
import { authProxy } from "./_lib.js";

const ALLOWED = new Set(["sign-in/social", "get-session", "sign-out"]);

async function handler(request) {
  const url = new URL(request.url);
  const path = url.searchParams.get("__p") || url.pathname.replace(/^\/api\/auth\/?/, "");
  // Google is the only sign-in method: everything except these endpoints (email/password sign-up,
  // password reset, account changes, ...) is refused here.
  if (!ALLOWED.has(path)) return new Response("Not allowed", { status: 403 });
  url.searchParams.delete("__p");
  url.pathname = "/api/auth/" + path;
  const init = { method: request.method, headers: request.headers };
  if (!["GET", "HEAD"].includes(request.method)) init.body = await request.text();
  return authProxy(new Request(url, init), path);
}

export { handler as GET, handler as POST };
