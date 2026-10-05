// Guaranteed illustrations: when no suitable licensed photo exists for a chapter, we draw an
// illustrative diagram of that chapter (its title and the topics it covers) in the report's colours.
import sharp from "sharp";
import { launchBrowser, lockedPage } from "./_browser.js";
import { fontFaces } from "./_build.js";

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

function shade(hex, f) {
  const n = parseInt(hex, 16);
  const ch = (v) => Math.round(v + (255 - v) * f).toString(16).padStart(2, "0");
  return ch((n >> 16) & 255) + ch((n >> 8) & 255) + ch(n & 255);
}

function diagramHtml(r, chapter, index, current = -1) {
  const primary = r.theme?.primary && r.theme.primary !== "000000" ? r.theme.primary : "1F3A5F";
  const light = shade(primary, 0.9), mid = shade(primary, 0.55);
  const rtl = r.rtl;
  const items = chapter.sections.map((s, i) => `<div class="node${i === current ? " on" : ""}"><b>${index + 1}.${i + 1}</b><span>${esc(s.title)}</span></div>`).join(`<div class="arrow">${rtl ? "&#x2190;" : "&#x2192;"}</div>`);
  return `<!doctype html><html dir="${rtl ? "rtl" : "ltr"}"><head><meta charset="utf-8"><style>${fontFaces()}
  html, body { margin: 0; }
  body { width: 1100px; height: 620px; font-family: "Amiri", "Times New Roman", serif; background: #fff; }
  .wrap { box-sizing: border-box; width: 1100px; height: 620px; padding: 40px 46px; display: flex; flex-direction: column; gap: 34px;
          background: radial-gradient(900px 400px at 50% 0%, #${light} 0%, #fff 70%); border: 2px solid #${mid}; }
  .hub { align-self: center; max-width: 900px; text-align: center; background: #${primary}; color: #fff; border-radius: 22px; padding: 22px 40px; font-size: 38px; font-weight: 700; line-height: 1.35; box-shadow: 0 12px 30px -16px #${primary}; }
  .hub small { display: block; font-size: 22px; font-weight: 400; opacity: .85; }
  .flow { flex: 1; display: flex; align-items: center; justify-content: center; gap: 14px; }
  .node { flex: 1; max-width: 300px; min-height: 170px; background: #fff; border: 3px solid #${primary}; border-radius: 18px; padding: 20px 18px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px; text-align: center; font-size: 27px; line-height: 1.35; color: #1b1f27; font-weight: 700; }
  .node.on { background: #${primary}; color: #fff; transform: scale(1.06); box-shadow: 0 14px 28px -14px #${primary}; }
  .node.on b { background: #fff; color: #${primary}; }
  .node b { min-width: 44px; padding: 0 6px; box-sizing: border-box; height: 44px; border-radius: 50%; background: #${mid}; color: #fff; display: grid; place-items: center; font-size: 24px; }
  .arrow { font-size: 44px; color: #${primary}; font-family: sans-serif; }
  </style></head><body><div class="wrap">
  <div class="hub"><small>${esc(r.chapterLabel ? r.chapterLabel(index) : "")}</small>${esc(chapter.title)}</div>
  <div class="flow">${items}</div></div></body></html>`;
}

/** Fills every section that has no photo or AI image with a rendered diagram, so no section is left without one. */
export async function ensureImages(r, chapterLabel) {
  const missing = [];
  r.chapters.forEach((c, ci) => c.sections.forEach((s, si) => { if (!s.image) missing.push([c, ci, s, si]); }));
  if (!missing.length) return;
  const browser = await launchBrowser();
  try {
    const page = await lockedPage(browser);
    await page.setViewport({ width: 1100, height: 620, deviceScaleFactor: 1.5 });
    for (const [c, ci, s, si] of missing) {
      await page.setContent(diagramHtml({ ...r, chapterLabel }, c, ci, si), { waitUntil: "load" });
      await page.evaluateHandle("document.fonts.ready").catch(() => {});
      const png = await page.screenshot({ type: "png", clip: { x: 0, y: 0, width: 1100, height: 620 } });
      const { data, info } = await sharp(png).jpeg({ quality: 88, mozjpeg: true }).toBuffer({ resolveWithObject: true });
      s.image = { data, width: info.width, height: info.height, kind: "diagram", credit: r.lang === "ar" ? "مخطط توضيحي من إعداد التقرير" : "Illustrative diagram prepared for this report" };
    }
  } finally {
    await browser.close();
  }
}
