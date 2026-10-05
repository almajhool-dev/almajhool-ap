// Builds the report content: outline → sections (in parallel) → introduction, conclusion, references.
import { chat, chatJson, pool } from "./_ai.js";
import { findReferences, formatRef } from "./_refs.js";
import { findImages } from "./_images.js";
import { styleInstructions } from "./_style.js";

export const LANGS = {
  ar: { name: "العربية", rtl: true, l: { intro: "المقدمة", conclusion: "الخاتمة", refs: "المصادر والمراجع", toc: "فهرس المحتويات", chapter: "الفصل", by: "إعداد الطالب", sup: "إشراف", dept: "القسم", year: "العام الدراسي", report: "تقرير بعنوان" } },
  en: { name: "English", rtl: false, l: { intro: "Introduction", conclusion: "Conclusion", refs: "References", toc: "Table of Contents", chapter: "Chapter", by: "Prepared by", sup: "Supervised by", dept: "Department", year: "Academic Year", report: "A Report on" } },
  fr: { name: "Français", rtl: false, l: { intro: "Introduction", conclusion: "Conclusion", refs: "Références", toc: "Table des matières", chapter: "Chapitre", by: "Préparé par", sup: "Sous la direction de", dept: "Département", year: "Année universitaire", report: "Rapport intitulé" } },
  es: { name: "Español", rtl: false, l: { intro: "Introducción", conclusion: "Conclusión", refs: "Referencias", toc: "Índice", chapter: "Capítulo", by: "Elaborado por", sup: "Supervisado por", dept: "Departamento", year: "Año académico", report: "Informe sobre" } },
  de: { name: "Deutsch", rtl: false, l: { intro: "Einleitung", conclusion: "Fazit", refs: "Literaturverzeichnis", toc: "Inhaltsverzeichnis", chapter: "Kapitel", by: "Erstellt von", sup: "Betreut von", dept: "Fachbereich", year: "Studienjahr", report: "Bericht über" } },
  tr: { name: "Türkçe", rtl: false, l: { intro: "Giriş", conclusion: "Sonuç", refs: "Kaynakça", toc: "İçindekiler", chapter: "Bölüm", by: "Hazırlayan", sup: "Danışman", dept: "Bölüm", year: "Akademik Yıl", report: "Rapor" } },
};


const STYLE = (langName) => `You are an experienced university professor writing in ${langName}.
Write in clear, precise, formal academic ${langName}, the way a careful human scholar writes:
- vary sentence length and structure; mix short and long sentences; connect ideas logically
- be concrete: definitions, mechanisms, examples, figures and well-known facts where relevant
- avoid filler, clichés, rhetorical questions, emojis, lists and markdown symbols (#, *, -)
- never mention that you are an AI, never address the reader, never add notes or meta-commentary
- output only the requested text in ${langName}.`;

function splitParas(text) {
  return text.split(/\n\s*\n|\n/).map((p) => p.replace(/^[#*\-•\d.\s]+(?=\S)/, (m) => (/^\d+\.\d/.test(m) ? m : "")).replace(/\*\*/g, "").trim()).filter((p) => p.length > 1);
}

function trimWords(paras, max) {
  const out = []; let n = 0;
  for (const t of paras) {
    const w = t.split(/\s+/).length;
    if (out.length && n + w > max) break;
    out.push(t); n += w;
  }
  return out;
}

function plan(pages, format, lang, images = false) {
  if (format === "pptx") {
    const slides = Math.max(6, Math.min(40, pages));
    const chapters = slides <= 8 ? 2 : slides <= 14 ? 3 : slides <= 24 ? 4 : 5;
    const perChapter = Math.max(1, Math.round((slides - 5 - chapters) / chapters));
    return { chapters, sections: Math.min(5, perChapter), words: 0 };
  }
  // Layout: cover + contents + references take ~3 pages; intro, each chapter and conclusion start on a new page.
  const wpp = lang === "ar" ? 250 : 360;
  const textPages = Math.max(4, pages - 3);
  const chapters = pages <= 7 ? 2 : pages <= 12 ? 3 : pages <= 25 ? 4 : 5;
  const sections = pages <= 7 ? 2 : pages <= 20 ? 3 : 4;
  const frontBack = Math.min(4, Math.max(1.2, textPages * 0.15));
  const chapterPages = Math.max(0.9, (textPages - frontBack) / chapters - (images ? 0.6 : 0));
  const words = Math.max(110, Math.round((chapterPages * wpp * 0.8 - 40) / sections));
  return { chapters, sections, words, introWords: Math.round(frontBack * 0.55 * wpp * 0.9), conclWords: Math.round(frontBack * 0.45 * wpp * 0.9) };
}

export async function buildContent(input) {
  const { title, lang, pages, format, department, mode, style } = input;
  const L = { ...LANGS[lang] };
  const p = plan(pages, format, lang, true); // every report carries illustrations
  const learned = mode === "advanced" && style ? style : null;
  if (learned?.avgParaWords && format !== "pptx") p.paraWords = Math.max(60, Math.min(220, learned.avgParaWords));
  const sys = { role: "system", content: STYLE(L.name) + styleInstructions(learned) };
  const stats = { ok: {}, fail: [], ms: {} };
  const t0 = Date.now();
  const script = lang === "ar" ? "arabic" : undefined;

  const outline = await chatJson([
    sys,
    { role: "user", content: `Create the outline of a university report titled: "${title}"${department ? ` (field: ${department})` : ""}.
Return ONLY valid JSON, no other text, in ${L.name}:
{"keywords_en":"3-6 English search keywords for the topic","keywords_ar":"3-6 Arabic search keywords for the topic","chapters":[{"title":"...","sections":["...","..."],"image_query":"2-4 English words naming a concrete photographable subject for this chapter"}]}
Exactly ${p.chapters} chapters, each with exactly ${p.sections} sections. Titles must be specific to the topic (no numbering, no words like "Chapter").` },
  ], { maxTokens: 1500, temperature: 0.6, stats });
  stats.ms.outline = Date.now() - t0;

  const chapters = (outline.chapters || []).slice(0, p.chapters).map((c) => ({
    title: String(c.title || "").replace(/^[\d.\-\s]+/, "").trim(),
    imageQuery: String(c.image_query || "").replace(/[^\p{L}\p{N} ]/gu, " ").trim().slice(0, 60),
    sections: (c.sections || []).slice(0, p.sections).map((s) => ({ title: String(s.title || s).replace(/^[\d.\-\s]+/, "").trim() })),
  })).filter((c) => c.title && c.sections.length);
  if (!chapters.length) throw new Error("BAD_OUTLINE");

  const outlineText = chapters.map((c, i) => `${i + 1}. ${c.title}: ${c.sections.map((s) => s.title).join("; ")}`).join("\n");
  const jobs = chapters.flatMap((c, ci) => c.sections.map((s, si) => ({ c, s, ci, si })));

  const sectionsDone = pool(jobs, Number(process.env.GEN_CONCURRENCY) || 8, async ({ c, s }) => {
    if (format === "pptx") {
      const text = await chat([sys, { role: "user", content: `Report: "${title}". Chapter: "${c.title}". Slide topic: "${s.title}".
Write 4 to 5 concise, informative bullet points for this presentation slide (each 12-22 words), one per line, no symbols or numbering.` }], { maxTokens: 700, script, stats });
      s.bullets = splitParas(text).slice(0, 5);
    } else {
      const text = await chat([sys, { role: "user", content: `Report title: "${title}".
Full outline:\n${outlineText}\n
Write the section "${s.title}" of the chapter "${c.title}".
Length: about ${p.words} words, in ${Math.max(2, Math.round(p.words / (p.paraWords || 110)))} well-developed paragraphs separated by a blank line.
Do not repeat the section title, do not write an introduction to the whole report, do not summarize at the end.` }], { maxTokens: Math.min(4000, Math.round(p.words * 3.2) + 400), script, stats });
      s.paragraphs = trimWords(splitParas(text), Math.round(p.words * 1.35));
    }
  }).then(() => { stats.ms.sections = Date.now() - t0; });

  const rest = Promise.all([
    chat([sys, { role: "user", content: format === "pptx"
      ? `Write 4 concise introduction bullet points (12-22 words each) for a presentation titled "${title}" with this outline:\n${outlineText}\nOne per line, no symbols.`
      : `Write the introduction of the university report "${title}" with this outline:\n${outlineText}\nAbout ${p.introWords} words in 2-4 paragraphs: context and importance of the topic, the problem it addresses, objectives, and a short description of how the report is organized. Do not write a heading.` }], { maxTokens: 2000, script, stats }),
    chat([sys, { role: "user", content: format === "pptx"
      ? `Write 4 concise conclusion bullet points (12-22 words each) for a presentation titled "${title}". One per line, no symbols.`
      : `Write the conclusion of the university report "${title}" with this outline:\n${outlineText}\nAbout ${p.conclWords} words in 2-3 paragraphs: main findings and a few practical recommendations. Do not write a heading.` }], { maxTokens: 1600, script, stats }),
    findReferences({ title, lang, keywordsAr: String(outline.keywords_ar || ""), keywordsEn: String(outline.keywords_en || ""), stats }),
    findImages(chapters.map((c) => c.imageQuery || ""), [String(outline.keywords_en || ""), String(department || "")]),
  ]);
  // Await both together so a failure in either is handled (no unhandled rejection).
  const [[intro, conclusion, refs, images]] = await Promise.all([rest, sectionsDone]);
  chapters.forEach((c, i) => { c.image = images[i] || null; });
  stats.ms.total = Date.now() - t0;

  return {
    ...input,
    L: L.l,
    rtl: L.rtl,
    intro: format === "pptx" ? splitParas(intro) : trimWords(splitParas(intro), Math.round(p.introWords * 1.35)),
    conclusion: format === "pptx" ? splitParas(conclusion) : trimWords(splitParas(conclusion), Math.round(p.conclWords * 1.35)),
    chapters,
    stats,
    references: refs.map(formatRef).sort((a, b) => a.localeCompare(b, lang)),
    chapterWord: learned?.chapterWord && (learned.lang === "ar") === (lang === "ar") ? learned.chapterWord : null,
  };
}
