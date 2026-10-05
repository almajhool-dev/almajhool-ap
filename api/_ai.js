// Text generation, tried in order: Vercel AI Gateway (authenticated automatically with the project's
// OIDC token, uses the account's gateway credits), then free keyless endpoints, then any optional API keys.
let oidcToken = "";
export function setOidcToken(t) { if (t) oidcToken = t; }

const PROVIDERS = [
  { id: "vercel", url: "https://ai-gateway.vercel.sh/v1/chat/completions", key: "AI_GATEWAY_API_KEY", oidc: true,
    models: ["google/gemini-3.5-flash-lite", "deepseek/deepseek-v4-flash", "google/gemini-2.5-flash"] },
  { id: "kilo", url: "https://api.kilo.ai/api/gateway/chat/completions", key: "KILO_API_KEY",
    models: ["nvidia/nemotron-3-ultra-550b-a55b:free", "qwen/qwen3.8-27b:free"], extra: { reasoning: { enabled: false } } },
  { id: "openrouter", url: "https://openrouter.ai/api/v1/chat/completions", key: "OPENROUTER_API_KEY", needsKey: true,
    models: ["nvidia/nemotron-3-ultra-550b-a55b:free", "qwen/qwen3.8-27b:free"] },
  { id: "gemini", url: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", key: "GEMINI_API_KEY", needsKey: true,
    models: ["gemini-flash-latest"], extra: { reasoning_effort: "low" } },
  { id: "groq", url: "https://api.groq.com/openai/v1/chat/completions", key: "GROQ_API_KEY", needsKey: true,
    models: ["openai/gpt-oss-120b", "llama-3.3-70b-versatile"] },
  { id: "llm7", url: "https://api.llm7.io/v1/chat/completions", key: "LLM7_API_KEY",
    models: ["GLM-5.3-Flash"], reasoning: true },
  { id: "ovh", url: "https://oai.endpoints.kepler.ai.cloud.ovh.net/v1/chat/completions", key: "OVH_API_KEY",
    models: ["gpt-oss-120b", "Meta-Llama-3_3-70B-Instruct"] },
];

const REASONING = /^(okay|ok,|alright|we need|we must|we should|i need|i will|i'll|let me|let's|the user|first,|so,? (we|i)|hmm)/i;

/** Returns the final answer only, or null when the model leaked its reasoning / ignored the format. */
function extractFinal(raw, { script } = {}) {
  let s = String(raw || "").replace(/<think>[\s\S]*?<\/think>/gi, "");
  const tagged = [...s.matchAll(/<final>([\s\S]*?)(?:<\/final>|$)/gi)].pop();
  if (tagged) s = tagged[1];
  else if (REASONING.test(s.trim()) || /\b(word count|let's craft|paragraph 1:)/i.test(s)) return null;
  s = s.replace(/<\/?final>/gi, "").replace(/^\s*```[a-z]*\s*|\s*```\s*$/gi, "").trim();
  if (script === "arabic") {
    const letters = s.match(/\p{L}/gu)?.length || 1;
    const arabic = s.match(/\p{Script=Arabic}/gu)?.length || 0;
    if (arabic / letters < 0.75) return null;
  }
  return s.length > 20 ? s : null;
}

export async function chat(messages, { maxTokens = 2500, temperature = 0.8, script, stats, timeoutMs = 70_000 } = {}) {
  messages = messages.map((m, i) => (i === messages.length - 1
    ? { ...m, content: `${m.content}\n\nOutput format: put ONLY the final text between <final> and </final>. Nothing outside the tags.` }
    : m));
  const errors = [];
  for (const p of PROVIDERS) {
    const key = process.env[p.key] || (p.oidc ? oidcToken || process.env.VERCEL_OIDC_TOKEN : "");
    if (p.disabled || ((p.needsKey || p.oidc) && !key)) continue;
    for (const model of p.models) {
      try {
        const ctrl = new AbortController();
        const timer = setTimeout(() => ctrl.abort(), timeoutMs);
        const res = await fetch(p.url, {
          method: "POST",
          signal: ctrl.signal,
          headers: { "Content-Type": "application/json", ...(key ? { Authorization: `Bearer ${key}` } : {}) },
          body: JSON.stringify({ model, messages, temperature, max_tokens: maxTokens + (p.reasoning ? 3500 : 2500), ...(p.extra || {}) }),
        }).finally(() => clearTimeout(timer));
        if (!res.ok) {
          errors.push(`${p.id}/${model}: ${res.status}`);
          if (res.status === 401 || res.status === 403) { p.disabled = true; break; } // account not enabled for this provider
          continue;
        }
        const data = await res.json();
        const text = extractFinal(data?.choices?.[0]?.message?.content, { script });
        if (text) { if (stats) stats.ok[`${p.id}/${model}`] = (stats.ok[`${p.id}/${model}`] || 0) + 1; return text; }
        errors.push(`${p.id}/${model}: unusable output`);
      } catch (e) {
        errors.push(`${p.id}/${model}: ${e.name === "AbortError" ? "timeout" : e.message}`);
      } finally {
        if (stats && errors.length) stats.fail.push(errors[errors.length - 1]);
      }
    }
  }
  console.error("All providers failed", errors);
  const err = new Error("AI_UNAVAILABLE");
  err.details = errors;
  throw err;
}

export function parseJson(text) {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("BAD_JSON");
  return JSON.parse(text.slice(start, end + 1));
}

export async function chatJson(messages, opts) {
  let last;
  for (let i = 0; i < 3; i++) {
    try { return parseJson(await chat(messages, opts)); } catch (e) { last = e; if (e.message === "AI_UNAVAILABLE") throw e; }
  }
  throw last;
}

const MAX_PARALLEL = 4; // free endpoints throttle bursts; 4 in flight keeps them fast

/** Runs async tasks with limited concurrency, preserving order. */
export async function pool(items, limit, fn) {
  limit = Math.min(limit, MAX_PARALLEL);
  const out = new Array(items.length);
  let i = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (i < items.length) { const k = i++; out[k] = await fn(items[k], k); }
  });
  await Promise.all(workers);
  return out;
}

/** Credential for Vercel AI Gateway (API key if configured, else the request's OIDC token). */
export function gatewayKey() {
  return process.env.AI_GATEWAY_API_KEY || oidcToken || process.env.VERCEL_OIDC_TOKEN || "";
}
