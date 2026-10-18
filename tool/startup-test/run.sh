#!/usr/bin/env bash
# فحص فتح التطبيق: نثبّت النسخة ونفتحها ونسجّل كل أخطاء النظام والتطبيق
set -uo pipefail
adb wait-for-device
echo "ABIS: $(adb shell getprop ro.product.cpu.abilist)"
PKG=com.almajhool.almajhool_app
for v in "$@"; do
  echo "=================== $v ==================="
  adb uninstall $PKG >/dev/null 2>&1
  adb install --no-incremental "$v.apk" 2>&1 | tail -2
  adb logcat -c
  adb shell am start -W -n $PKG/.MainActivity 2>&1 | tail -5
  sleep 20
  adb shell screencap -p /sdcard/s1.png; adb pull /sdcard/s1.png shot1.png >/dev/null 2>&1
  sleep 25
  adb shell screencap -p /sdcard/s2.png; adb pull /sdcard/s2.png shot2.png >/dev/null 2>&1
  PID=$(adb shell pidof $PKG | tr -d '\r')
  echo "[$v] pid=$PID"
  adb shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity" | head -3
  adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp" | head -3
  echo "--- logcat ($v) ---"
  adb logcat -d | grep -E "flutter|Flutter|AndroidRuntime|FATAL|almajhool|ANR|E/|W/System.err|DartVM|libc|DEBUG|Choreographer|ActivityManager" | grep -vE "chatty|GoogleApiManager|Finsky|Gmscore" | head -250
done

# نتيجة الفحص: يفشل إذا التطبيق طاح أو علق بخطأ إضافة
L=$(adb logcat -d)
if [ -z "$PID" ] || echo "$L" | grep -qE "FATAL EXCEPTION|NoSuchMethodError|ClassNotFoundException|UnsatisfiedLinkError"; then
  echo "STARTUP: FAIL"; exit 1
fi
echo "STARTUP: OK"
