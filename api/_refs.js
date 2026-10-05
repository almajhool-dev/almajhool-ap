// Real references only: every entry comes from Crossref's public metadata (registered DOIs).
// The AI never writes references; at most it picks which of the real candidates are relevant.
import { chat } from "./_ai.js";

const UA = "AcademicReportEngine/2.0 (https://academic-report-engine.vercel.app; mailto:reports@academic-report-engine.app)";
const TYPES = new Set(["journal-article", "proceedings-article", "book", "book-chapter", "monograph", "dissertation", "report", "posted-content"]);
const AR = /\p{Script=Arabic}/u;

async function crossref(query, rows = 25) {
  if (!query) return [];
  const url = `https://api.crossref.org/works?query.bibliographic=${encodeURIComponent(query)}&rows=${rows}` +
    "&filter=from-pub-date:2000-01-01&select=DOI,title,author,issued,container-title,publisher,volume,issue,page,type,score";
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 15_000);
  try {
    const res = await fetch(url, { headers: { "User-Agent": UA }, signal: ctrl.signal });
    if (!res.ok) return [];
    const j = await res.json();
    return j?.message?.items || [];
  } catch { return []; } finally { clearTimeout(t); }
}

function clean(s) {
  return String(s || "").replace(/<[^>]+>/g, "").replace(/[\u200b-\u200f\u202a-\u202e\u2066-\u2069]/g, "").replace(/\u0640/g, "")
    .replace(/\s*:\s*,\s*/g, ": ").replace(/\s+([,.:؛،])/g, "$1").replace(/\s+/g, " ").trim();
}
const TITLES = /^(أ\.?\s?د\.?|ا\.?\s?د\.?|م\.?\s?م\.?|أ\.?\s?م\.?\s?د?\.?|د\.|م\.|Dr\.?|Prof\.?)\s+/u;

function normalize(it) {
  const title = clean((it.title || [])[0]);
  const authors = (it.author || []).map((a) => ({ given: clean(a.given).replace(TITLES, ""), family: clean(a.family || a.name).replace(TITLES, "") })).filter((a) => a.family);
  const year = it.issued?.["date-parts"]?.[0]?.[0];
  if (!title || title.length < 8 || !authors.length || !year || !TYPES.has(it.type)) return null;
  return {
    doi: it.DOI, title, authors, year, type: it.type,
    venue: clean((it["container-title"] || [])[0]) || clean(it.publisher),
    volume: clean(it.volume), issue: clean(it.issue), pages: clean(it.page),
    arabic: AR.test(title), score: it.score || 0,
  };
}

/** APA 7 style; Arabic works keep full Arabic names in natural order. */
export function formatRef(r) {
  const ar = r.arabic;
  const names = r.authors.slice(0, 6).map((a) => (ar
    ? [a.given, a.family].filter(Boolean).join(" ")
    : `${a.family}${a.given ? ", " + a.given.split(/[\s-]+/).filter(Boolean).map((g) => g[0] + ".").join(" ") : ""}`));
  const who = ar ? names.join("، ") : names.length > 1 ? names.slice(0, -1).join(", ") + ", & " + names.at(-1) : names[0];
  const more = r.authors.length > 6 ? (ar ? " وآخرون" : " et al.") : "";
  const vol = r.volume ? (ar ? `، ${r.volume}` : `, ${r.volume}`) + (r.issue ? `(${r.issue})` : "") : "";
  const pg = r.pages ? (ar ? `، ${r.pages}` : `, ${r.pages}`) : "";
  const venue = r.venue ? (ar ? ` ${r.venue}${vol}${pg}.` : ` ${r.venue}${vol}${pg}.`) : "";
  return `${who}${more} (${r.year}). ${r.title}.${venue} https://doi.org/${r.doi}`;
}

/**
 * Finds 8–12 real, relevant publications. Arabic (Iraqi and regional journals) first for Arabic reports,
 * then international literature. Queries run in parallel.
 */
export async function findReferences({ title, lang, keywordsAr, keywordsEn, stats }) {
  const queries = lang === "ar"
    ? [title, keywordsAr, `${keywordsAr || title} العراق`, keywordsEn]
    : [title, keywordsEn, `${keywordsEn || title} Iraq`, keywordsAr];
  const lists = await Promise.all([...new Set(queries.filter(Boolean))].map((q) => crossref(q)));
  const seen = new Set();
  let cands = [];
  for (const list of lists) for (const it of list) {
    const r = normalize(it);
    if (!r || seen.has(r.doi.toLowerCase()) || seen.has(r.title.toLowerCase())) continue;
    seen.add(r.doi.toLowerCase()); seen.add(r.title.toLowerCase());
    cands.push(r);
  }
  if (lang === "ar") cands.sort((a, b) => (b.arabic - a.arabic) || (b.score - a.score));
  cands = cands.slice(0, 40);
  if (!cands.length) return [];

  // Let the model choose relevant items by number only (it cannot alter or add references).
  let chosen = cands.slice(0, 12);
  try {
    const list = cands.map((c, i) => `${i + 1}. ${c.title} (${c.venue || c.type}, ${c.year})`).join("\n");
    const ans = await chat([{ role: "user", content: `Topic of a university report: "${title}".
Below are real publications. Pick the 8 to 12 most relevant to the topic${lang === "ar" ? ", preferring Arabic-language and Iraqi/Arab research when relevant" : ""}.
Answer with their numbers only, comma-separated.\n\n${list}` }], { maxTokens: 200, temperature: 0.1, stats, timeoutMs: 30_000 });
    const nums = [...new Set((ans.match(/\d+/g) || []).map(Number))].filter((n) => n >= 1 && n <= cands.length);
    if (nums.length >= 5) chosen = nums.slice(0, 12).map((n) => cands[n - 1]);
  } catch { /* keep top-ranked */ }
  return chosen;
}
