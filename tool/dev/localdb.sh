#!/usr/bin/env bash
# قاعدة محلية لاختبار supabase/schema.sql (Postgres 16، قاعدة sb على المنفذ 5432)
# الاستعمال: tool/dev/localdb.sh           ← تشغيل + تطبيق المخطط مرتين (يتأكد إنه يتعاد بدون أخطاء)
#            tool/dev/localdb.sh --fresh   ← يمسح القاعدة ويبنيها من الصفر
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 9
TMP="$(mktemp -d)"
pg_lsclusters 2>/dev/null | grep -qE "^16 +main .* online" || pg_ctlcluster 16 main start || { echo "postgres: ما اشتغل"; exit 2; }
P="sudo -u postgres psql -p 5432 -v ON_ERROR_STOP=1 -q"
[ "$1" = "--fresh" ] && $P -d postgres -c "drop database if exists sb" >/dev/null
if ! $P -d postgres -tAc "select 1 from pg_database where datname='sb'" | grep -q 1; then
  $P -d postgres -c "create database sb" >/dev/null || exit 3
  $P -d sb < "$ROOT/tool/dev/supabase_stubs.sql" > "$TMP/stubs.log" 2>&1 || { echo "stubs FAILED:"; grep -m5 ERROR "$TMP/stubs.log"; exit 4; }
  echo "sb: انبنت من جديد (محاكاة Supabase)"
fi
for i in 1 2; do
  if $P -d sb --single-transaction < "$ROOT/supabase/schema.sql" > "$TMP/apply$i.log" 2>&1; then echo "apply $i OK"
  else echo "apply $i FAILED:"; grep -m5 -E "ERROR|error" "$TMP/apply$i.log"; exit 5; fi
done
rm -rf "$TMP"
