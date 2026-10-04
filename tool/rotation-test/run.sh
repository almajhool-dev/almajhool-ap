#!/usr/bin/env bash
# فحص تشغيل: النسخة الشاملة ثم المصغّرة، ونطبع أي انهيار.
set -uo pipefail
adb wait-for-device
adb shell getprop ro.product.cpu.abilist
I="adb install --no-incremental"
launch() {
  adb logcat -c
  adb shell monkey -p com.almajhool.almajhool_app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 25
  PID=$(adb shell pidof com.almajhool.almajhool_app | tr -d '\r')
  echo "[$1] pid=$PID"
  adb logcat -d | grep -A25 "FATAL EXCEPTION" | grep -E "Exception|Error|Caused by|at " | head -30
  [ -n "$PID" ]
}
$I rotated.apk && launch universal && U=ok || U=fail
adb uninstall com.almajhool.almajhool_app >/dev/null
$I split.apk && launch split && S=ok || S=fail
echo "RESULT universal=$U split=$S"
[ "$S" = ok ] && echo "RESULT=PASS"
