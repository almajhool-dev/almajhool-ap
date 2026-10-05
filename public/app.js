"use strict";
const $ = (s) => document.querySelector(s);
const VERIFIER = "neon_auth_session_verifier";
const FORMAT_LABEL = { docx: "Word", pdf: "PDF", pptx: "PowerPoint", xlsx: "Excel" };
const state = { me: null, logo: null, fileUrl: null, busy: false, logos: null, profiles: [], source: null };

function toast(msg, err = false) {
  const t = $("#toast");
  t.textContent = msg;
  t.classList.toggle("err", err);
  t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.hidden = true), 4200);
}
function show(view) {
  for (const id of ["dash", "form-view", "result-view"]) $("#" + id).hidden = id !== view;
  window.scrollTo({ top: 0, behavior: "smooth" });
}

/* ---------- Auth ---------- */
async function signInGoogle() {
  const btn = $("#btn-google");
  btn.disabled = true;
  btn.querySelector("span").textContent = "جارٍ التحويل إلى Google…";
  try {
    const res = await fetch("/api/auth/sign-in/social", {
      method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider: "google", callbackURL: location.origin + "/" }),
    });
    const j = await res.json();
    if (!j.url) throw new Error(j.message || j.error || "تعذّر بدء تسجيل الدخول");
    location.href = j.url;
  } catch (e) {
    toast(e.message, true);
    btn.disabled = false;
    btn.querySelector("span").textContent = "تسجيل الدخول عبر Google";
  }
}
async function signOut() {
  await fetch("/api/auth/sign-out", { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: "{}" }).catch(() => {});
  location.replace("/");
}
async function loadMe() {
  const params = new URLSearchParams(location.search);
  if (params.has(VERIFIER)) {
    await fetch(`/api/auth/get-session?${VERIFIER}=${encodeURIComponent(params.get(VERIFIER))}`, { credentials: "same-origin" }).catch(() => {});
    params.delete(VERIFIER);
    history.replaceState(null, "", location.pathname + (params.toString() ? "?" + params : ""));
  }
  const me = await fetch("/api/me", { credentials: "same-origin", cache: "no-store" }).then((r) => r.json()).catch(() => ({ user: null }));
  state.me = me.user ? me : null;
  return state.me;
}

/* ---------- Dashboard ---------- */
function renderDash() {
  const u = state.me.user;
  $("#acct-avatar").src = u.image || "/icon.svg";
  $("#acct-name").textContent = u.name || u.email;
  $("#hello-name").textContent = (u.name || "").split(" ")[0] || "";
  const list = $("#history-list");
  list.replaceChildren();
  const reports = state.me.reports || [];
  $("#history-empty").hidden = reports.length > 0;
  for (const r of reports) {
    const li = document.createElement("li");
    const t = document.createElement("span");
    t.className = "t";
    t.textContent = r.title;
    const m = document.createElement("span");
    m.className = "m";
    const d = new Date(r.created_at).toLocaleDateString("ar-IQ", { day: "numeric", month: "short" });
    m.textContent = `${d} · ${r.pages} صفحة`;
    const tag = document.createElement("span");
    tag.className = "tag";
    tag.textContent = FORMAT_LABEL[r.format] || r.format;
    m.append(tag);
    li.append(t, m);
    list.append(li);
  }
}

/* ---------- Form ---------- */
const form = $("#report-form");
form.pages.addEventListener("input", () => ($("#pages-out").textContent = form.pages.value));
form.addEventListener("change", (e) => {
  if (e.target.name === "format") $("#pptx-note").hidden = form.format.value !== "pptx";
  if (e.target.name === "lang") form.title.dir = form.lang.value === "ar" ? "rtl" : "ltr";
});

$("#logo-input").addEventListener("change", async (e) => {
  const f = e.target.files[0];
  if (!f) return;
  if (!/^image\/(png|jpeg|webp)$/.test(f.type)) { toast("الصيغ المدعومة: PNG أو JPG أو WEBP", true); return; }
  if (f.size > 2 * 1024 * 1024) { toast("حجم الصورة يجب أن يكون أقل من 2 ميغابايت", true); return; }
  state.logo = await new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = rej; r.readAsDataURL(f); });
  $("#logo-q").value = "";
  showLogo("شعار مخصص — ستُزال الخلفية تلقائيًا");
});
$("#logo-clear").addEventListener("click", () => {
  state.logo = null;
  $("#logo-input").value = "";
  $("#logo-preview").hidden = true;
  $("#logo-clear").hidden = true;
  $("#logo-name").textContent = "";
  $("#logo-q").value = "";
  updatePreview();
});

function readForm() {
  const v = (n) => form[n].value.trim();
  const radio = (n) => form.querySelector(`input[name="${n}"]:checked`)?.value;
  const students = [...document.querySelectorAll("#students input")].map((i) => i.value.trim()).filter(Boolean);
  const data = {
    title: v("title"), lang: form.lang.value, pages: Number(form.pages.value), format: radio("format"),
    students, supervisor: v("supervisor"), university: v("university"), college: v("college"), department: v("department"),
    mode: radio("mode"), topicColor: radio("topicColor"),
  };
  if (data.mode === "advanced") {
    Object.assign(data, { palette: radio("palette"), border: radio("border"), background: radio("background") });
    const sid = radio("styleId");
    if (sid && sid !== "0") data.styleId = Number(sid);
  }
  if (state.source) data.source = state.source.text;
  if (data.title.length < 3 && !state.source) return [null, "اكتب عنوان التقرير أو ارفع ملفًا نستدل به", "title"];
  if (data.university.length < 2) return [null, "اكتب اسم الجامعة أو المعهد", "university"];
  if (!students.length) return [null, "اكتب اسم طالب واحد على الأقل", null];
  if (state.logo) data.logo = state.logo;
  return [data];
}

/* ---------- Source file (read in the browser) ---------- */
const SOURCE_MAX = 150000;
function loadScript(src) {
  return new Promise((res, rej) => {
    if (document.querySelector(`script[src="${src}"]`)) return res();
    const s = document.createElement("script"); s.src = src; s.onload = res; s.onerror = rej; document.head.append(s);
  });
}
/** Some PDFs store Arabic lines in visual order (words reversed); restore reading order when detected. */
function fixArabicOrder(text) {
  const lines = text.split("\n");
  const arabicLine = (l) => (l.match(/\p{Script=Arabic}/gu) || []).length > l.replace(/\s/g, "").length * 0.6;
  let front = 0, back = 0;
  for (const l of lines) {
    if (!arabicLine(l)) continue;
    const t = l.trim();
    if (/^[.،؛:!؟]\s*\p{Script=Arabic}/u.test(t)) front++;
    if (/\p{Script=Arabic}\s*[.،؛:!؟]$/u.test(t)) back++;
  }
  if (front <= back || front < 2) return text;
  return lines.map((l) => (arabicLine(l) ? l.trim().split(/\s+/).reverse().map((w) => w.replace(/^([.،؛:!؟]+)(.+)$/u, "$2$1")).join(" ").replace(/\s+([.،؛:!؟])/gu, "$1") : l)).join("\n");
}
async function extractText(file) {
  const ext = (file.name.split(".").pop() || "").toLowerCase();
  if (ext === "txt" || file.type === "text/plain") return { text: await file.text(), pages: null };
  const buf = await file.arrayBuffer();
  if (ext === "pdf" || file.type === "application/pdf") {
    const pdfjs = await import("/vendor/pdf.min.mjs");
    pdfjs.GlobalWorkerOptions.workerSrc = "/vendor/pdf.worker.min.mjs";
    const doc = await pdfjs.getDocument({ data: buf, cMapUrl: "/vendor/cmaps/", cMapPacked: true, isEvalSupported: false }).promise;
    let text = "";
    const n = Math.min(doc.numPages, 500);
    for (let i = 1; i <= n; i++) {
      const page = await doc.getPage(i);
      const tc = await page.getTextContent();
      text += tc.items.map((it) => it.str + (it.hasEOL ? "\n" : " ")).join("") + "\n\n";
      $("#source-status").textContent = `جارٍ القراءة… صفحة ${i} من ${n}`;
      if (text.length > SOURCE_MAX * 1.3) break;
    }
    return { text: fixArabicOrder(text), pages: doc.numPages };
  }
  if (ext === "docx") {
    await loadScript("/vendor/mammoth.browser.min.js");
    const r = await window.mammoth.extractRawText({ arrayBuffer: buf });
    return { text: r.value, pages: null };
  }
  throw new Error("صيغة غير مدعومة — ارفع PDF أو Word (.docx) أو ملفًا نصيًا");
}
$("#source-input").addEventListener("change", async (e) => {
  const f = e.target.files[0];
  e.target.value = "";
  if (!f) return;
  if (f.size > 60 * 1024 * 1024) { toast("حجم الملف كبير جدًا (الحد 60 ميغابايت)", true); return; }
  const status = $("#source-status");
  status.className = "small muted";
  status.textContent = "جارٍ قراءة الملف…";
  try {
    let { text, pages } = await extractText(f);
    text = text.replace(/[ \t]+/g, " ").replace(/\n{3,}/g, "\n\n").trim();
    const words = text.split(/\s+/).filter(Boolean).length;
    if (text.length < 200) throw new Error("لم نجد نصًا كافيًا في الملف — قد يكون PDF مصوّرًا (صور بلا نص). جرّب نسخة Word أو PDF نصي.");
    const cut = text.length > SOURCE_MAX;
    state.source = { name: f.name, text: text.slice(0, SOURCE_MAX) };
    status.className = "small";
    status.textContent = `✓ ${f.name} — ${words.toLocaleString("ar-IQ")} كلمة${pages ? ` من ${pages} صفحة` : ""}${cut ? " (سنستخدم أول 150 ألف حرف)" : ""}`;
    $("#source-clear").hidden = false;
  } catch (err) {
    state.source = null;
    status.className = "small error";
    status.textContent = err.message || "تعذّر قراءة الملف";
  }
});
$("#source-clear").addEventListener("click", () => { state.source = null; $("#source-status").textContent = ""; $("#source-clear").hidden = true; });

/* ---------- Students ---------- */
function addStudent(value = "") {
  const box = $("#students");
  if (box.children.length >= 10) { toast("الحد الأقصى 10 طلاب", true); return; }
  const row = document.createElement("div");
  row.className = "student-row";
  const input = document.createElement("input");
  input.maxLength = 80;
  input.placeholder = `اسم الطالب ${box.children.length + 1}`;
  input.value = value;
  input.addEventListener("input", updatePreview);
  const del = document.createElement("button");
  del.type = "button"; del.textContent = "×"; del.title = "حذف";
  del.addEventListener("click", () => { if (box.children.length > 1) row.remove(); else input.value = ""; updatePreview(); });
  row.append(input, del);
  box.append(row);
  return input;
}
addStudent();
$("#add-student").addEventListener("click", () => addStudent().focus());

/* ---------- Mode & live cover preview ---------- */
const PAL = { navy: "#1B2A6B", burgundy: "#6D1A2A", emerald: "#0F6B4F", charcoal: "#36454F" };
const BG = { none: "#fff", ivory: "#FBF8F1", mist: "#F4F7FB", sage: "#F3F7F2" };
function updatePreview() {
  const radio = (n) => form.querySelector(`input[name="${n}"]:checked`)?.value;
  const pv = $("#preview");
  pv.style.setProperty("--p", PAL[radio("palette")] || PAL.navy);
  pv.style.setProperty("--t", radio("topicColor") === "blue" ? "#1F4E9A" : "#000");
  pv.style.setProperty("--bg", BG[radio("background")] || "#fff");
  pv.classList.toggle("framed", radio("border") !== "none");
  $("#pv-uni").textContent = form.university.value.trim() || "اسم الجامعة";
  $("#pv-title").textContent = form.title.value.trim() || "عنوان الموضوع";
  const names = [...document.querySelectorAll("#students input")].map((i) => i.value.trim()).filter(Boolean);
  $("#pv-names").replaceChildren(...(names.length ? names : ["الطالب الأول", "الطالب الثاني"]).slice(0, 6).map((n) => { const d = document.createElement("div"); d.textContent = n; return d; }));
  $("#pv-logo").hidden = !state.logo;
  if (state.logo) $("#pv-logo").src = state.logo;
}
form.addEventListener("input", updatePreview);
form.addEventListener("change", (e) => {
  if (e.target.name === "mode") {
    $("#advanced").hidden = form.querySelector('input[name="mode"]:checked').value !== "advanced";
    if (!$("#advanced").hidden) loadProfiles();
  }
  updatePreview();
});

/* ---------- Logo library (instant search) ---------- */
const norm = (s) => String(s || "").toLowerCase().replace(/[\u064B-\u065F\u0670\u0640]/g, "").replace(/[أإآٱ]/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه").replace(/\s+/g, " ").trim();
async function logos() {
  if (!state.logos) state.logos = await fetch("/logos.json").then((r) => r.json()).then((l) => l.map((x) => ({ ...x, k: norm(`${x.ar} ${x.en}`) }))).catch(() => []);
  return state.logos;
}
let logoTimer, active = -1;
const COUNTRY = { IQ: "العراق", SA: "السعودية", EG: "مصر", JO: "الأردن", SY: "سوريا", LB: "لبنان", KW: "الكويت", AE: "الإمارات", QA: "قطر", BH: "البحرين", OM: "عُمان", YE: "اليمن", PS: "فلسطين", DZ: "الجزائر", MA: "المغرب", TN: "تونس", LY: "ليبيا", SD: "السودان" };
function renderLogoResults(items, q, live = false) {
  const ul = $("#logo-results");
  ul.replaceChildren();
  active = -1;
  for (const it of items) {
    const li = document.createElement("li");
    li.setAttribute("role", "option");
    const name = document.createElement("span");
    name.textContent = it.ar || it.en;
    const meta = document.createElement("small");
    meta.textContent = it.c ? COUNTRY[it.c] || it.c : "ويكيبيديا";
    li.append(name, meta);
    li.addEventListener("mousedown", (e) => { e.preventDefault(); pickLogo(it); });
    ul.append(li);
  }
  if (!live && q.length >= 3) {
    const more = document.createElement("li");
    more.className = "more";
    more.textContent = items.length ? `لم تجده؟ ابحث أوسع عن «${q}»` : `ابحث في ويكيبيديا عن «${q}»`;
    more.addEventListener("mousedown", (e) => { e.preventDefault(); liveLogoSearch(q); });
    ul.append(more);
  }
  if (live && !items.length) {
    const li = document.createElement("li"); li.className = "more"; li.textContent = "لم نجد شعارًا — استخدم «رفع شعار مخصص»";
    ul.append(li);
  }
  ul.hidden = !ul.children.length;
}
async function liveLogoSearch(q) {
  const ul = $("#logo-results");
  ul.replaceChildren(Object.assign(document.createElement("li"), { className: "more", textContent: "جارٍ البحث…" }));
  const j = await fetch(`/api/logo?q=${encodeURIComponent(q)}`, { credentials: "same-origin" }).then((r) => r.json()).catch(() => ({ results: [] }));
  renderLogoResults((j.results || []).map((x) => ({ ...x, s: x.w })), q, true);
}
$("#logo-q").addEventListener("input", (e) => {
  clearTimeout(logoTimer);
  const q = e.target.value.trim();
  if (q.length < 2) { $("#logo-results").hidden = true; return; }
  logoTimer = setTimeout(async () => {
    const n = norm(q);
    const list = (await logos()).filter((x) => x.k.includes(n));
    list.sort((a, b) => (a.c === "IQ" ? 0 : 1) - (b.c === "IQ" ? 0 : 1) || a.k.indexOf(n) - b.k.indexOf(n));
    renderLogoResults(list.slice(0, 8), q);
  }, 80);
});
$("#logo-q").addEventListener("keydown", (e) => {
  const items = [...$("#logo-results").children];
  if (!items.length || $("#logo-results").hidden) return;
  if (e.key === "ArrowDown" || e.key === "ArrowUp") {
    e.preventDefault();
    active = (active + (e.key === "ArrowDown" ? 1 : -1) + items.length) % items.length;
    items.forEach((li, i) => li.setAttribute("aria-selected", i === active));
  } else if (e.key === "Enter" && active >= 0) {
    e.preventDefault();
    items[active].dispatchEvent(new MouseEvent("mousedown"));
  } else if (e.key === "Escape") $("#logo-results").hidden = true;
});
$("#logo-q").addEventListener("blur", () => setTimeout(() => ($("#logo-results").hidden = true), 150));

async function pickLogo(it) {
  $("#logo-results").hidden = true;
  $("#logo-q").value = it.ar || it.en;
  $("#logo-name").textContent = "جارٍ تحميل الشعار…";
  try {
    const r = await fetch(`/api/logo?src=${encodeURIComponent(it.s)}&f=${encodeURIComponent(it.f)}`);
    if (!r.ok) throw new Error();
    const blob = await r.blob();
    state.logo = await new Promise((res, rej) => { const fr = new FileReader(); fr.onload = () => res(fr.result); fr.onerror = rej; fr.readAsDataURL(blob); });
    showLogo(it.ar || it.en);
    if (!form.university.value.trim() && it.ar) form.university.value = it.ar;
  } catch {
    $("#logo-name").textContent = "";
    toast("تعذّر تحميل هذا الشعار، جرّب «رفع شعار مخصص»", true);
  }
}
function showLogo(label) {
  $("#logo-preview").src = state.logo;
  $("#logo-preview").hidden = false;
  $("#logo-clear").hidden = false;
  $("#logo-name").textContent = label;
  updatePreview();
}

/* ---------- Style samples (advanced) ---------- */
async function loadProfiles() {
  const j = await fetch("/api/style", { credentials: "same-origin" }).then((r) => r.json()).catch(() => ({ profiles: [] }));
  state.profiles = j.profiles || [];
  renderProfiles();
}
function renderProfiles(selectId) {
  const ul = $("#profiles");
  const current = selectId ?? form.querySelector('input[name="styleId"]:checked')?.value ?? "0";
  ul.replaceChildren();
  const item = (id, title, sub, removable) => {
    const li = document.createElement("li");
    const label = document.createElement("label");
    const r = document.createElement("input");
    r.type = "radio"; r.name = "styleId"; r.value = String(id); r.checked = String(id) === String(current);
    const t = document.createElement("span");
    t.textContent = title;
    if (sub) { const s = document.createElement("small"); s.textContent = sub; t.append(s); }
    label.append(r, t);
    li.append(label);
    if (removable) {
      const del = document.createElement("button");
      del.type = "button"; del.className = "link"; del.textContent = "حذف";
      del.addEventListener("click", async () => {
        await fetch(`/api/style?id=${id}`, { method: "DELETE", credentials: "same-origin" });
        loadProfiles();
      });
      li.append(del);
    }
    ul.append(li);
  };
  item(0, "بدون نموذج — أسلوب أكاديمي قياسي", "", false);
  for (const p of state.profiles) item(p.id, p.name, p.summary, true);
}
$("#sample-input").addEventListener("change", async (e) => {
  const files = [...e.target.files].slice(0, 3);
  e.target.value = "";
  if (!files.length) return;
  if (files.reduce((n, f) => n + f.size, 0) > 3 * 1024 * 1024) { toast("مجموع حجم النماذج يجب أن يكون أقل من 3 ميغابايت", true); return; }
  const status = $("#sample-status");
  status.textContent = "جارٍ تحليل النموذج…";
  try {
    const data = await Promise.all(files.map((f) => new Promise((res, rej) => { const fr = new FileReader(); fr.onload = () => res(fr.result); fr.onerror = rej; fr.readAsDataURL(f); })));
    const r = await fetch("/api/style", {
      method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: $("#sample-name").value.trim() || files[0].name.replace(/\.[^.]+$/, ""), files: data }),
    });
    const j = await r.json();
    if (!r.ok) throw new Error(j.error || "تعذّر تحليل النموذج");
    status.textContent = "✓ تم الحفظ: " + j.summary;
    await loadProfiles();
    renderProfiles(j.id);
  } catch (err) {
    status.textContent = "";
    toast(err.message, true);
  }
});

/* ---------- Generation ---------- */
const STEPS = [
  [0, "نضع مخطط الفصول والمباحث…"],
  [8, "نكتب المقدمة والفصل الأول…"],
  [30, "نكتب بقية الفصول والمباحث…"],
  [55, "نبحث عن مصادر حقيقية في المجلات العراقية والعربية…"],
  [70, "نختار الصور التوضيحية ونكتب الخاتمة…"],
  [88, "نصمّم الغلاف وننسّق الصفحات…"],
  [120, "اللمسات الأخيرة على الملف…"],
];
let timer;
function startProgress(pages) {
  const expected = 70 + pages * 9; // seconds
  const t0 = Date.now();
  $("#working").hidden = false; $("#done").hidden = true; $("#failed").hidden = true;
  clearInterval(timer);
  timer = setInterval(() => {
    const s = (Date.now() - t0) / 1000;
    const pct = Math.min(95, (s / expected) * 100);
    $("#work-bar").style.width = pct + "%";
    const scaled = (s / expected) * 140;
    $("#work-step").textContent = [...STEPS].reverse().find(([at]) => scaled >= at)[1];
  }, 700);
}

async function generate(e) {
  e?.preventDefault();
  if (state.busy) return;
  const [data, err, field] = readForm();
  const errBox = $("#form-error");
  if (!data) { errBox.textContent = err; errBox.hidden = false; (field ? form[field] : $("#students input"))?.focus(); return; }
  errBox.hidden = true;
  state.busy = true;
  state.last = data;
  $("#btn-generate").disabled = true;
  show("result-view");
  startProgress(data.pages);
  try {
    const res = await fetch("/api/generate", {
      method: "POST", credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data),
    });
    if (res.status === 401) { location.replace("/"); return; }
    if (!res.ok) {
      const j = await res.json().catch(() => ({}));
      throw new Error(j.error || (res.status === 504 ? "انتهت مهلة الإنشاء. جرّب عددًا أقل من الصفحات." : "تعذّر إنشاء التقرير"));
    }
    const blob = await res.blob();
    if (state.fileUrl) URL.revokeObjectURL(state.fileUrl);
    state.fileUrl = URL.createObjectURL(blob);
    const fromHeader = decodeURIComponent((res.headers.get("Content-Disposition") || "").match(/filename\*=UTF-8''([^;]+)/)?.[1] || "");
    const name = (fromHeader || `${(data.title || "report").slice(0, 80)}.${data.format}`).replace(/[\\/:*?"<>|]/g, "");
    const dl = $("#btn-download");
    dl.href = state.fileUrl;
    dl.download = name;
    $("#btn-open").href = state.fileUrl;
    $("#btn-open").hidden = data.format !== "pdf"; // browsers can only preview PDF directly
    $("#done-name").textContent = `${name} — ${(blob.size / 1024).toFixed(0)} KB`;
    $("#work-bar").style.width = "100%";
    $("#working").hidden = true;
    $("#done").hidden = false;
    loadMe().then((m) => m && renderDash());
  } catch (err) {
    $("#working").hidden = true;
    $("#failed").hidden = false;
    $("#fail-msg").textContent = err.message === "Failed to fetch" ? "انقطع الاتصال. تحقق من الإنترنت وحاول مجددًا." : err.message;
  } finally {
    clearInterval(timer);
    state.busy = false;
    $("#btn-generate").disabled = false;
  }
}

form.addEventListener("submit", generate);
$("#btn-google").addEventListener("click", signInGoogle);
$("#btn-logout").addEventListener("click", signOut);
$("#btn-new").addEventListener("click", () => { show("form-view"); updatePreview(); });
$("#btn-back").addEventListener("click", () => show("dash"));
$("#btn-another").addEventListener("click", () => { form.title.value = ""; show("form-view"); form.title.focus(); });
$("#btn-retry").addEventListener("click", () => generate());

(async function boot() {
  const me = await loadMe();
  document.body.classList.remove("booting");
  if (!me) { $("#login").hidden = false; return; }
  $("#app").hidden = false;
  renderDash();
  show("dash");
})();
