// دالة إرسال إشعارات Google (FCM HTTP v1).
// تستدعيها قاعدة البيانات مع سر مشترك؛ حساب الخدمة محفوظ سرًا في قاعدة البيانات.
const SB_URL = "https://smjkxsqvdpywumghvnfv.supabase.co";
const PUB = "sb_publishable_xqWRKqnOIKKqKgPJrdP5TA_GA7PCSiV";

type SA = { project_id: string; client_email: string; private_key: string };
let cfg: { secret: string; sa: SA; at: number } | null = null;
let oauth: { token: string; exp: number; email: string } | null = null;

function b64url(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function rpc(name: string, args: Record<string, unknown>) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: PUB, "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  return r.ok ? await r.json() : null;
}

async function loadConfig(secret: string): Promise<SA | null> {
  if (cfg && cfg.secret === secret && Date.now() - cfg.at < 10 * 60_000) return cfg.sa;
  const sa = (await rpc("push_config", { p_secret: secret })) as SA | null;
  if (!sa || !sa.private_key) return null;
  cfg = { secret, sa, at: Date.now() };
  return sa;
}

async function accessToken(sa: SA): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (oauth && oauth.email === sa.client_email && oauth.exp - 120 > now) return oauth.token;
  const unsigned = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" })) + "." + b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const jwt = unsigned + "." + b64url(sig);
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" + jwt,
  });
  const j = await r.json();
  if (!j.access_token) throw new Error("oauth failed: " + JSON.stringify(j).slice(0, 200));
  oauth = { token: j.access_token, exp: now + (j.expires_in ?? 3600), email: sa.client_email };
  return oauth.token;
}

Deno.serve(async (req) => {
  if (req.method === "GET") return Response.json({ ok: true, service: "push" });
  const body = await req.json().catch(() => null);
  const secret = body?.secret as string | undefined;
  if (!secret) return new Response("forbidden", { status: 403 });
  const sa = await loadConfig(secret);
  if (!sa) return new Response("forbidden", { status: 403 });

  let token: string;
  try {
    token = await accessToken(sa);
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }

  const messages = (Array.isArray(body.messages) ? body.messages : []).slice(0, 500);
  const invalid: string[] = [];
  const errors: string[] = [];
  let sent = 0;
  await Promise.all(messages.map(async (m: Record<string, unknown>) => {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ message: m }),
    });
    if (r.ok) {
      sent++;
      return;
    }
    const t = await r.text();
    if (r.status === 404 || t.includes("UNREGISTERED") || (r.status === 400 && t.includes("registration token"))) {
      invalid.push(String(m.token));
    } else if (errors.length < 3) {
      errors.push(`${r.status} ${t.slice(0, 160)}`);
    }
  }));
  if (invalid.length) await rpc("push_drop_tokens", { p_secret: secret, p_tokens: invalid });
  return Response.json({ sent, invalid: invalid.length, errors });
});
