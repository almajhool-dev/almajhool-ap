#!/usr/bin/env bash
# فحص مختصر: التحليل + الاختبارات — يطبع المشاكل والخلاصة بس (يوفّر توكنز)
# الاستعمال: tool/dev/check.sh [test/x_test.dart ...]   (بدون ملفات = كل الاختبارات)
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 9
export PATH="/home/claude/sdk/flutter/bin:$PATH"
a=$(flutter analyze 2>&1)
n=$(echo "$a" | grep -oE "[0-9]+ issues? found" | grep -oE "^[0-9]+")
new=$(echo "$a" | grep -E "^ *(error|warning|info) •" | grep -v "lib/services/push_service.dart")
if [ -n "$new" ]; then echo "ANALYZE: مشاكل جديدة:"; echo "$new"; else echo "ANALYZE: ok (${n:-0} قديمة معروفة)"; fi
t=$(flutter test "$@" 2>&1)
echo "$t" | grep -E "\[E\]$|^ *Expected:|^ *Actual:|^ *Which:|EXCEPTION CAUGHT|^Error:" | head -40
last=$(echo "$t" | grep -E "All tests passed|Some tests failed|No tests ran|Error" | tail -1)
echo "TEST: ${last:-$(echo "$t" | tail -1)}"
[ -z "$new" ] && echo "$last" | grep -q "All tests passed"
