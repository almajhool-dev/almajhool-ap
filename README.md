# المبرمج المجهول — تطبيق تواصل ومراسلة (Android)

تطبيق Flutter + Supabase: مراسلة فورية، مجموعات، جهات اتصال، إشعارات، وضع داكن/فاتح، واجهة عربية RTL، ولوحة تحكم للمدير مع **زر تشغيل/إيقاف التطبيق**.

## لماذا Supabase؟
- **Postgres حقيقي**: علاقات منظمة (مستخدمون، محادثات، أعضاء، رسائل…) بدل مستندات متفرقة.
- **Realtime** مدمج للرسائل الفورية، مؤشر الكتابة، والمتصلين الآن (Presence).
- **Row Level Security**: الصلاحيات تُفرض داخل قاعدة البيانات نفسها، فلا يستطيع أي مستخدم قراءة محادثات غيره حتى لو عدّل التطبيق.
- **Auth + Storage** جاهزان، وكلمات المرور مشفّرة (bcrypt) ولا تُخزن كنص.
- خطة مجانية كافية للبداية، ولا يحتاج ملف `google-services.json` داخل التطبيق.

## هيكل المشروع
```
lib/
  core/          config.dart (مفاتيح الخادم) · theme.dart (الألوان والوضع الداكن/الفاتح)
  models/        models.dart (Profile, ConversationSummary, Message, Member, ...)
  services/      core_services.dart (Cache/Offline, Connectivity) · media_service.dart · local_notifications.dart
  repositories/  chat_repository.dart (+Outbox) · user_repositories.dart · social_repositories.dart (+Admin)
  providers/     providers.dart (Session, Theme, AppStatus=تشغيل/إيقاف, ChatHub=Realtime)
  screens/       gate (Splash/صيانة/حظر) · auth · home · chat · groups · contacts · search
                 notifications · profile · settings · admin (لوحة التحكم)
  widgets/       common.dart · message_bubble.dart
  utils/         helpers.dart (تنسيق، تحقق من المدخلات، رسائل الأخطاء)
supabase/schema.sql      قاعدة البيانات + الصلاحيات + التخزين + Realtime (ملف واحد)
admin/index.html         لوحة تحكم ويب (اختيارية) — نفس صلاحيات اللوحة داخل التطبيق
tool/ci_build.sh         سكربت البناء (APK + Release APK + AAB)
tool/patch_android.py    ضبط Manifest/Gradle/التوقيع/الاسم تلقائيًا
.github/workflows/build.yml   بناء تلقائي على GitHub ونشر APK في Releases
```

## 1) إعداد Supabase (مرة واحدة، 5 دقائق)
1. أنشئ مشروعًا مجانيًا على https://supabase.com
2. **SQL Editor → New query** → الصق محتوى `supabase/schema.sql` كاملًا → **Run**.
3. **Authentication → Providers → Email**: مفعّل (افتراضيًا). لتجربة أسرع يمكنك إيقاف *Confirm email*.
4. **Authentication → Email Templates → Reset Password**: أضف السطر `رمزك: {{ .Token }}` حتى يصل رمز استعادة كلمة المرور.
5. من **Project Settings → API** انسخ: `Project URL` و `anon public key`.

## 2) تحميل التطبيق على هاتفك
- افتح صفحة **Releases** في المستودع ← نزّل `almajhool-app.apk` ← ثبّته (اسمح بالتثبيت من مصادر غير معروفة).
- أول تشغيل: يطلب منك Supabase URL و anon key (مرة واحدة فقط).
  - أو أضفها كـ **Secrets** في المستودع (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) من Settings → Secrets and variables → Actions، فتُدمج في كل نسخة تلقائيًا.

## 3) تفعيل حساب المدير ولوحة التحكم
بعد إنشاء حسابك من التطبيق، شغّل في SQL Editor:
```sql
update public.profiles set is_admin = true where username = 'اسم_المستخدم_الخاص_بك';
```
ثم: **الإعدادات ← لوحة التحكم** داخل التطبيق:
- **زر تشغيل/إيقاف التطبيق**: عند الإيقاف تظهر رسالة الصيانة لكل المستخدمين فورًا ولا يستطيعون الإرسال (المدير يبقى قادرًا على الدخول لإعادة التشغيل).
- إحصائيات، إدارة المستخدمين (حظر/إلغاء، منح صلاحية مدير)، البلاغات وحذف المحتوى، إدارة المجموعات، إشعار عام.
- نفس اللوحة متوفرة على المتصفح: `admin/index.html`.

## 4) البناء محليًا (اختياري)
يتطلب Flutter (stable) و Java 17:
```bash
bash tool/ci_build.sh        # يولّد android/ ويضبطه ثم يبني الثلاثة
```
أو يدويًا بعد التشغيل الأول:
```bash
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release
# مع تضمين المفاتيح:
flutter build apk --release --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxx
```
الملفات: `build/app/outputs/flutter-apk/app-release.apk` و `build/app/outputs/bundle/release/app-release.aab`.

## 5) توقيع Release للنشر على Google Play
```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 upload-keystore.jks   # انسخ الناتج
```
أضف Secrets: `KEYSTORE_BASE64`، `KEYSTORE_PASSWORD`، `KEY_ALIAS` (upload)، `KEY_PASSWORD`.
بدونها تُوقّع نسخة Release بمفتاح debug (تُثبّت على الهاتف عاديًا، لكن لا تُقبل في Google Play).
**لا ترفع ملف `.jks` أو كلمات مروره إلى المستودع أبدًا.**

## الإعدادات والمفاتيح التي تضعها بنفسك
| المفتاح | أين | إلزامي؟ |
|---|---|---|
| Supabase URL + anon key | داخل التطبيق أول مرة، أو Secrets | نعم |
| `is_admin = true` لحسابك | SQL Editor | للوحة التحكم |
| Keystore secrets | GitHub Secrets | فقط لـ Google Play |
| قالب بريد Reset Password | Supabase Auth | لاستعادة كلمة المرور |

## الأمان
- RLS على كل الجداول؛ العمليات الحساسة (حذف/تعديل/صلاحيات/إدارة) عبر دوال `security definer` تتحقق من الصلاحية.
- الملفات الخاصة في bucket `chat-media` بمسار `<conversation_id>/...` لا يقرؤها إلا أعضاء المحادثة، وتُعرض بروابط موقّعة مؤقتة.
- Rate limiting: حد 20 رسالة / 10 ثوانٍ لكل مستخدم على مستوى قاعدة البيانات.
- الحظر يمنع المراسلة وطلبات التواصل من الطرفين، والمحظور من الإدارة لا يستطيع الإرسال.
- الاتصال مشفّر HTTPS/WSS، ولا تُعرض بيانات حساسة (البريد غير موجود في جدول profiles العام).

## ملاحظات
- **الإشعارات**: تظهر على الجهاز أثناء عمل التطبيق أو وجوده في الخلفية. إشعارات Push والتطبيق مغلق كليًا تتطلب ربط Firebase Cloud Messaging (خطوة لاحقة اختيارية).
- **بدون إنترنت**: آخر المحادثات والرسائل محفوظة محليًا، والرسائل النصية تُرسل تلقائيًا عند عودة الاتصال.

صُنع بواسطة **المبرمج المجهول**.
