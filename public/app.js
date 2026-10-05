"use strict";
const $ = (s) => document.querySelector(s);
const VERIFIER = "neon_auth_session_verifier";
const FORMAT_LABEL = { docx: "Word", pdf: "PDF", pptx: "PowerPoint", xlsx: "Excel" };
const state = { me: null, logo: null, fileUrl: null, busy: false };

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
  $("#logo-preview").src = state.logo;
  $("#logo-preview").hidden = false;
  $("#logo-clear").hidden = false;
});
$("#logo-clear").addEventListener("click", () => {
  state.logo = null;
  $("#logo-input").value = "";
  $("#logo-preview").hidden = true;
  $("#logo-clear").hidden = true;
});

function readForm() {
  const v = (n) => form[n].value.trim();
  const data = {
    title: v("title"), lang: form.lang.value, pages: Number(form.pages.value), format: form.format.value,
    student: v("student"), supervisor: v("supervisor"), university: v("university"), department: v("department"),
  };
  if (data.title.length < 3) return [null, "اكتب عنوان التقرير", "title"];
  if (data.student.length < 2) return [null, "اكتب اسم الطالب", "student"];
  if (data.university.length < 2) return [null, "اكتب اسم الجامعة أو المعهد", "university"];
  if (state.logo) data.logo = state.logo;
  return [data];
}

/* ---------- Generation ---------- */
const STEPS = [
  [0, "نضع مخطط الفصول والمباحث…"],
  [8, "نكتب المقدمة والفصل الأول…"],
  [30, "نكتب بقية الفصول والمباحث…"],
  [60, "نكتب الخاتمة ونجمع المراجع…"],
  [85, "نصمّم الغلاف وننسّق الصفحات…"],
  [120, "اللمسات الأخيرة على الملف…"],
];
let timer;
function startProgress(pages) {
  const expected = 50 + pages * 8; // seconds
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
  if (!data) { errBox.textContent = err; errBox.hidden = false; form[field].focus(); return; }
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
    const name = `${data.title.slice(0, 80).replace(/[\\/:*?"<>|]/g, "")}.${data.format}`;
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
$("#btn-new").addEventListener("click", () => show("form-view"));
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
