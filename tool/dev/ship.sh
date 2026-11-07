#!/usr/bin/env bash
# الاستعمال: tool/dev/ship.sh <sha> "<وصف قصير>"  — بس لما المالك يطلب النشر
# نشر نسخة: ينتظر نجاح البناء + فحص التشغيل، يتأكد من توقيع الملف، وبعدها ينشر ويتأكد من الخادم
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 9
S=$(git rev-parse "$1") || exit 8; MSG=$2; R=repos/almajhool-dev/almajhool-ap
echo "sha=$S"
until B=$(gh api "$R/actions/runs?head_sha=$S" --jq '[.workflow_runs[]|select(.name=="Build APK")][0].id') && [ -n "$B" ] && [ "$B" != null ]; do sleep 20; done
until [ "$(gh api $R/actions/runs/$B --jq .status)" = completed ]; do sleep 30; done
BC=$(gh api $R/actions/runs/$B --jq .conclusion); N=$(gh api $R/actions/runs/$B --jq .run_number); echo "build=$BC n=$N"
[ "$BC" = success ] || exit 2
T=$(gh api "$R/actions/runs?head_sha=$S" --jq '[.workflow_runs[]|select(.name=="Startup test")][0].id')
if [ -z "$T" ] || [ "$T" = null ]; then
  SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  gh api -X POST $R/actions/workflows/startup-test.yml/dispatches -f ref=main >/dev/null
  until T=$(gh api "$R/actions/workflows/startup-test.yml/runs?event=workflow_dispatch&per_page=5" --jq "[.workflow_runs[]|select(.created_at >= \"$SINCE\")][0].id") && [ -n "$T" ] && [ "$T" != null ]; do sleep 10; done
fi
until [ "$(gh api $R/actions/runs/$T --jq .status)" = completed ]; do sleep 30; done
TC=$(gh api $R/actions/runs/$T --jq .conclusion); echo "startup-test=$TC"; [ "$TC" = success ] || exit 3
D=$(mktemp -d); curl -sSL -o $D/app.apk "https://github.com/almajhool-dev/almajhool-ap/releases/download/v1.0.$N/almajhool-app.apk"
FP=$(unzip -p $D/app.apk 'META-INF/*.RSA' 2>/dev/null | openssl pkcs7 -inform DER -print_certs 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
echo "signer=$FP"; case "$FP" in 17:D4:60:1E:F4:67:77:34*) ;; *) echo BADSIG; exit 4;; esac
git pull -q --rebase; printf '{"paused": false, "latest_tag": "v1.0.%s"}\n' $N > release/control.json
git add release/control.json; git -c user.name=almajhool-dev -c user.email=almajhool-dev@users.noreply.github.com commit -qm "نشر v1.0.$N: $MSG"; git push -q || { git pull -q --rebase && git push -q; }
for i in $(seq 1 60); do r=$(curl -s -X POST "https://smjkxsqvdpywumghvnfv.supabase.co/rest/v1/rpc/latest_release" -H "apikey: sb_publishable_xqWRKqnOIKKqKgPJrdP5TA_GA7PCSiV" -H "Content-Type: application/json" -d '{}'); echo "$r" | grep -q "\"build\": $N" && { echo "PUBLISHED $N sha256=$(echo "$r" | grep -o '"sha256": "[0-9a-f]*"')"; exit 0; }; sleep 15; done; echo NOTLIVE
