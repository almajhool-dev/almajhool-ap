"""يجدد مفتاح Google (OAuth) لإرسال الإشعارات ويحفظه في قاعدة البيانات.
يعمل داخل GitHub Actions فقط: قاعدة البيانات تتحقق من رمز GitHub قبل أي شيء."""
import base64, json, os, sys, time, urllib.request

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


sa = rpc("push_refresh_config", {"p_gh": GH})
if not sa:
    print("service account not uploaded yet (or verification failed) — nothing to do")
    sys.exit(0)

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

body = ("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" + jwt).encode()
req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body,
                             headers={"Content-Type": "application/x-www-form-urlencoded"}, method="POST")
with urllib.request.urlopen(req, timeout=30) as r:
    tok = json.loads(r.read())

ok = rpc("push_set_access", {"p_gh": GH, "p_access": tok["access_token"], "p_expires": int(tok.get("expires_in", 3600))})
print("stored:", ok)
print("diag:", json.dumps({k: v for k, v in rpc("push_diag", {}).items() if k != "recent"}))
if not ok:
    sys.exit(1)
