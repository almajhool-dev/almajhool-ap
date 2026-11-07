#!/usr/bin/env bash
# هل دالة بالخادم وصلت؟ (الخادم يحدّث نفسه من main كل 10 دقايق)
# الاستعمال: tool/dev/live.sh <function> ['{"arg":"dummy"}'] [wait]
#   مرّر أسماء معاملات الدالة الحقيقية (بقيم وهمية) وإلا الخادم ما يلكاها.
# LIVE = موجودة (حتى لو الزائر ممنوع منها)، MISSING = بعد ما وصلت
U=https://smjkxsqvdpywumghvnfv.supabase.co; K=sb_publishable_xqWRKqnOIKKqKgPJrdP5TA_GA7PCSiV
f=${1:?اسم الدالة}; args=${2:-'{}'}; tries=1; [ "${3:-}" = wait ] || [ "${2:-}" = wait ] && tries=40
[ "$args" = wait ] && args='{}'
for i in $(seq 1 "$tries"); do
  r=$(curl -s -X POST "$U/rest/v1/rpc/$f" -H "apikey: $K" -H "Content-Type: application/json" -d "$args")
  if echo "$r" | grep -q '"PGRST202"'; then
    [ "$i" -lt "$tries" ] && { sleep 30; continue; }
    echo "MISSING: $f"; exit 1
  fi
  echo "LIVE: $f"; exit 0
done
