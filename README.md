# محرّك التقارير الأكاديمية — Academic Report Engine

منصة ويب لإنشاء تقارير وبحوث جامعية منسّقة وجاهزة للطباعة بصيغ **Word / PDF / PowerPoint / Excel**:
غلاف أكاديمي رسمي، فهرس، فصول ومباحث، مقدمة وخاتمة، وقائمة مراجع — بالعربية وعدة لغات.

**الموقع:** https://academic-report-engine.vercel.app

## المكوّنات
| الجزء | التقنية |
|---|---|
| الواجهة | HTML/CSS/JS بدون إطار، خط Cairo مستضاف ذاتيًا |
| الخادم | Vercel Functions (Node 22) |
| تسجيل الدخول | Google عبر Neon Auth، كوكيز HttpOnly + Secure + SameSite=Strict |
| قاعدة البيانات | Neon Postgres (المستخدمون، سجل التقارير، تقييد الطلبات) |
| الكتابة | نماذج ذكاء اصطناعي عبر Vercel AI Gateway أو نقاط مجانية، مع تبديل تلقائي عند الفشل |
| الملفات | `docx` · `pptxgenjs` · `exceljs` · PDF عبر Chromium (`@sparticuz/chromium`) + `pdf-lib` |

## الحماية
- HTTPS إجباري مع HSTS، وسياسة CSP صارمة (لا سكربتات أو موارد خارجية)، و`X-Frame-Options: DENY`.
- تسجيل الدخول بـ Google فقط؛ وكيل المصادقة يرفض أي مسار آخر (تسجيل بالبريد، إعادة كلمة المرور…).
- فحص المصدر (Origin) لكل طلب تعديل إضافة إلى SameSite=Strict ضد CSRF.
- تقييد الطلبات: 20 طلبًا/10 دقائق لكل IP، و6 تقارير/ساعة و25/يوم لكل مستخدم.
- تنقية كل المدخلات (أحرف تحكم، علامات HTML، أحرف اتجاه مخفية) وحدود أطوال صارمة.
- الصور المرفوعة: فحص البصمة (PNG/JPEG/WEBP فقط) ثم إعادة ترميز كاملة بـ sharp تزيل أي حمولة مخفية.
- توليد PDF داخل متصفح معزول مع تعطيل JavaScript وحظر كل الطلبات الشبكية.
- استعلامات SQL كلها مُعامَلة (parameterized).

## متغيرات البيئة
| المتغير | الوصف |
|---|---|
| `DATABASE_URL` | رابط Neon Postgres |
| `NEON_AUTH_BASE_URL` | رابط Neon Auth |
| `NEON_AUTH_COOKIE_SECRET` | سر توقيع الكوكيز (32 حرفًا فأكثر) |
| `GEMINI_API_KEY` / `GROQ_API_KEY` / `OPENROUTER_API_KEY` | اختيارية — تزيد سرعة وثبات الكتابة |

## الجداول
```sql
CREATE TABLE app_users (id text PRIMARY KEY, email text, name text, image text, created_at timestamptz DEFAULT now(), last_seen timestamptz DEFAULT now());
CREATE TABLE reports (id bigserial PRIMARY KEY, user_id text REFERENCES app_users(id) ON DELETE CASCADE, title text NOT NULL, lang text, format text, pages int, created_at timestamptz DEFAULT now());
CREATE TABLE rate_hits (key text NOT NULL, at timestamptz NOT NULL DEFAULT now());
CREATE INDEX rate_hits_key_at ON rate_hits(key, at);
CREATE INDEX reports_user ON reports(user_id, created_at DESC);
```

## التشغيل محليًا
```bash
npm install
npm run build        # ينسخ الخطوط ويجهّز pptxgenjs
npx vercel dev
```
