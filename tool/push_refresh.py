"""يجدد مفتاح Google (OAuth) لإرسال الإشعارات ويحفظه في قاعدة البيانات.
يعمل داخل GitHub Actions فقط: قاعدة البيانات تتحقق من رمز GitHub قبل أي شيء."""
import base64, json, os, sys, time, urllib.parse, urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

SB = "https://smjkxsqvdpywumghvnfv.supabase.co"
PUB = "sb_publishable_xqWRKqnOIKKqKgPJrdP5TA_GA7PCSiV"
GH = os.environ["GH_TOKEN"]


def rpc(name, args):
    req = urllib.request.Request(
        f"{SB}/rest/v1/rpc/{name}", data=json.dumps(args).encode(),
        headers={"apikey": PUB, "Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read() or b"null")


def b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def oauth(sa):
    now = int(time.time())
    head = b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claim = b64(json.dumps({
        "iss": sa["client_email"],
        "scope": "https://www.googleapis.com/auth/firebase.messaging",
        "aud": "https://oauth2.googleapis.com/token",
        "iat": now, "exp": now + 3600,
    }).encode())
    key = serialization.load_pem_private_key(sa["private_key"].encode(), password=None)
    sig = key.sign(f"{head}.{claim}".encode(), padding.PKCS1v15(), hashes.SHA256())
    jwt = f"{head}.{claim}.{b64(sig)}"
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": jwt}).encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


cfg = None
for attempt in range(5):
    try:
        cfg = rpc("push_refresh_config", {"p_gh": GH})
        break
    except Exception as e:  # noqa: BLE001
        print("config fetch failed:", e)
        time.sleep(20)
if not cfg:
    print("GitHub verification FAILED")
    sys.exit(1)

tok = None
pending = cfg.get("pending")
if pending:
    try:
        tok = oauth(pending)
        print("pending service account accepted by Google -> promote:", rpc("push_promote", {"p_gh": GH}))
    except Exception as e:  # noqa: BLE001
        print("pending service account rejected:", str(e)[:200])
        tok = None

if tok is None:
    sa = cfg.get("sa")
    if not sa:
        print("verified OK — no service account yet, nothing to do")
        sys.exit(0)
    tok = oauth(sa)

ok = rpc("push_set_access", {"p_gh": GH, "p_access": tok["access_token"], "p_expires": int(tok.get("expires_in", 3600))})
print("stored:", ok)
d = rpc("push_diag", {})
print("diag:", json.dumps({k: v for k, v in d.items() if k != "recent"}))
sys.exit(0 if ok else 1)
