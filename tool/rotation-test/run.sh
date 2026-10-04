#!/usr/bin/env bash
# يجرب على محاكي أندرويد: النسخة الحالية ← تحديث بالمفتاح الجديد (لازم ينجح)
# ← نسخة مزوّرة بالمفتاح القديم فقط (لازم تنرفض).
set -uo pipefail
adb wait-for-device
adb shell getprop ro.build.version.sdk
echo ">> install current (old key)"
adb install old.apk || { echo "RESULT=FAIL_INSTALL_OLD"; exit 1; }
echo ">> upgrade to rotated"
adb install -r rotated.apk || { echo "RESULT=FAIL_UPGRADE"; exit 1; }
echo ">> try fake (old key only) over rotated"
if adb install -r fake.apk; then echo "RESULT=FAIL_FAKE_ACCEPTED"; exit 1; fi
echo ">> rotated again over itself (next update)"
adb install -r rotated.apk || { echo "RESULT=FAIL_REUPDATE"; exit 1; }
echo "RESULT=PASS"
