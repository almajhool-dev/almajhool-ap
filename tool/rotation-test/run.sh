#!/usr/bin/env bash
# فحص على محاكي: نسخة قديمة (المفتاح القديم) ← التحديث الجديد المصغّر (لازم ينجح ويشتغل)
# ← نسخة مزوّرة بالمفتاح القديم (لازم تنرفض) ← النسخة الشاملة فوقه.
set -uo pipefail
adb wait-for-device
adb shell getprop ro.build.version.sdk
I="adb install --no-incremental"
$I old.apk || { echo "RESULT=FAIL_INSTALL_OLD"; exit 1; }
$I -r split.apk || { echo "RESULT=FAIL_UPGRADE_SPLIT"; exit 1; }
adb shell monkey -p com.almajhool.almajhool_app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 25
PID=$(adb shell pidof com.almajhool.almajhool_app | tr -d '\r')
echo "pid=$PID"
adb logcat -d | grep -E "FATAL|AndroidRuntime|libc  *:|Abort message" | head -20
[ -n "$PID" ] || { echo "RESULT=FAIL_APP_NOT_RUNNING"; exit 1; }
if $I -r fake.apk; then echo "RESULT=FAIL_FAKE_ACCEPTED"; exit 1; fi
$I -r rotated.apk || { echo "RESULT=FAIL_UNIVERSAL"; exit 1; }
echo "RESULT=PASS"
