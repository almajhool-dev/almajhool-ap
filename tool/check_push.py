"""حارس إشعارات Google: يوقف البناء إذا أي تغيير بالتطبيق ممكن يعطّل الإشعارات.
يشتغل تلقائيًا قبل كل بناء (tool/ci_build.sh)."""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def read(p):
    with open(os.path.join(ROOT, p), encoding="utf-8") as f:
        return f.read()

errors = []
push = read("lib/services/push_service.dart")
patch = read("tool/patch_android.py")
pubspec = read("pubspec.yaml")
gate = read("lib/screens/gate.dart")
main = read("lib/main.dart")

# 1) التسجيل لازم يكمل حتى لو علك طلب الإذن أو تأخر Google
if "requestPermission(" in push and not re.search(r"requestPermission\([^)]*\)\s*\.timeout", push):
    errors.append("requestPermission بدون مهلة (timeout) — ممكن يعلّك التسجيل للأبد")
if not re.search(r"getToken\(\)\s*\.timeout", push):
    errors.append("getToken بدون مهلة (timeout)")
# 2) الطريق البديل من أندرويد مباشرة + إعادة المحاولة التلقائية
for need, why in [("fcmDiag", "طلب الرمز من أندرويد مباشرة (fcmDiag) انشال"),
                  ("_retry = Timer", "إعادة المحاولة التلقائية انشالت"),
                  ("register_fcm2", "تسجيل الرمز بالخادم انشال"),
                  ("_starting", "منع الطلبات المتزامنة انشال")]:
    if need not in push:
        errors.append(why)
if '"fcmDiag"' not in patch:
    errors.append("معالج fcmDiag بـ MainActivity انشال")
# 3) إعداد Google الجديد يكسر getToken بمكتبة Flutter
if "firebase_messaging_installation_id_enabled" in patch:
    errors.append("firebase_messaging_installation_id_enabled يعطّل getToken — لا تضيفه")
# 4) لازم التطبيق يشغّل الإشعارات بعد الدخول
if "PushService.start()" not in gate or "PushService.init()" not in main:
    errors.append("تشغيل PushService (init/start) انشال من main/gate")
for dep in ("firebase_core", "firebase_messaging"):
    if not re.search(rf"^\s+{dep}:", pubspec, re.M):
        errors.append(f"{dep} انشال من pubspec.yaml")

if errors:
    print("❌ حارس الإشعارات أوقف البناء:")
    for e in errors:
        print("  -", e)
    sys.exit(1)
print("✅ حارس الإشعارات: كل شي سليم")
