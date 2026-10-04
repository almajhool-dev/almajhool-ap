#!/usr/bin/env bash
# توقيع التطبيق بمفتاح جديد سري مع «سلسلة تدوير» من المفتاح القديم (APK Signature Scheme v3).
# النتيجة: التحديث ينزل فوق النسخة الحالية طبيعي، وأي نسخة مزوّرة موقّعة بالمفتاح القديم
# ما تنزل فوق التطبيق بعد هذا التحديث (أندرويد 9 فما فوق).
# الاستخدام: sign_rotate.sh <in.apk> <out.apk>
set -euo pipefail
set +x
IN="$1"; OUT="$2"
SB_URL="${SB_URL:-https://smjkxsqvdpywumghvnfv.supabase.co}"
SB_KEY="${SB_KEY:-sb_publishable_xqWRKqnOIKKqKgPJrdP5TA_GA7PCSiV}"
: "${GH_TOKEN:?GH_TOKEN required}"

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
BT="$(ls -d "${ANDROID_HOME:-$ANDROID_SDK_ROOT}"/build-tools/* | sort -V | tail -1)"
APKSIGNER="$BT/apksigner"
echo ">> apksigner: $BT"

# المفتاح القديم (الموجود بالمشروع)
cp signing/almajhool.jks "$W/old.jks"
OLD_STORE="$(grep '^storePassword=' signing/signing.properties | cut -d= -f2-)"
OLD_KEY="$(grep '^keyPassword=' signing/signing.properties | cut -d= -f2-)"
OLD_ALIAS="$(grep '^keyAlias=' signing/signing.properties | cut -d= -f2-)"
export OLD_STORE OLD_KEY

# مفتاح جديد مرشّح (يُستخدم فقط إذا ماكو مفتاح محفوظ)
CAND_PASS="$(python3 -c 'import secrets;print(secrets.token_urlsafe(30))')"
keytool -genkeypair -keystore "$W/cand.jks" -storetype PKCS12 -alias almajhool2 -keyalg RSA -keysize 4096 \
  -validity 36500 -dname "CN=Almajhool, O=Almajhool, C=IQ" -storepass "$CAND_PASS" -keypass "$CAND_PASS" >/dev/null 2>&1
CAND_B64="$(base64 -w0 "$W/cand.jks")"

python3 - "$W" "$CAND_B64" "$CAND_PASS" <<'PY'
import json, os, sys, urllib.request, base64
w, ks, pw = sys.argv[1], sys.argv[2], sys.argv[3]
req = urllib.request.Request(os.environ.get('SB_URL', 'https://smjkxsqvdpywumghvnfv.supabase.co') + '/rest/v1/rpc/ci_signing',
    data=json.dumps({'p_gh': os.environ['GH_TOKEN'], 'p_ks': ks, 'p_pass': pw}).encode(),
    headers={'apikey': os.environ.get('SB_KEY', 'sb_publishable_xqWRKqnOIKKqKgPJrdP5TA_GA7PCSiV'),
             'Content-Type': 'application/json'})
r = json.loads(urllib.request.urlopen(req, timeout=30).read() or 'null')
if not r or 'ks' not in r:
    print('>> signing key unavailable'); sys.exit(3)
open(os.path.join(w, 'new.jks'), 'wb').write(base64.b64decode(r['ks']))
open(os.path.join(w, 'new.pass'), 'w').write(r['pass'])
print('>> signing key ready (stored=%s)' % ('same' if r['ks'] == ks else 'existing'))
PY
NEW_PASS="$(cat "$W/new.pass")"
echo "::add-mask::$NEW_PASS"
export NEW_PASS

"$APKSIGNER" rotate --out "$W/lineage" \
  --old-signer --ks "$W/old.jks" --ks-key-alias "$OLD_ALIAS" --ks-pass env:OLD_STORE --key-pass env:OLD_KEY \
  --new-signer --ks "$W/new.jks" --ks-key-alias almajhool2 --ks-pass env:NEW_PASS --key-pass env:NEW_PASS

"$APKSIGNER" sign \
  --ks "$W/old.jks" --ks-key-alias "$OLD_ALIAS" --ks-pass env:OLD_STORE --key-pass env:OLD_KEY \
  --next-signer --ks "$W/new.jks" --ks-key-alias almajhool2 --ks-pass env:NEW_PASS --key-pass env:NEW_PASS \
  --lineage "$W/lineage" --rotation-min-sdk-version 28 \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
  --out "$OUT" "$IN"

"$APKSIGNER" verify -v --print-certs "$OUT" | grep -E "Verified using|Signer|SHA-256" | head -20
echo ">> rotated signature OK"
