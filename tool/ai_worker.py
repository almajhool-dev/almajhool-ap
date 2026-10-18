# عامل المنشورات التلقائية (يُشغَّل من GitHub Actions)
"""يساعد المساعد الذكي بشغلتين ما يكدر يسويهن الخادم بنفسه:
1) يجيب أخبار الأمن السيبراني من مواقع عالمية موثوقة كل نص ساعة ويخزنها بقاعدة البيانات.
2) لما يكتب المساعد منشور جديد، يطلب صورة تناسبه من ChatGPT (OpenAI) ويرفعها لتخزين التطبيق.
قاعدة البيانات تتحقق من رمز GitHub قبل أي شي، ومفتاح OpenAI ما ينحفظ بالمستودع أبدًا."""
import base64
import email.utils
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

SB = "https://smjkxsqvdpywumghvnfv.supabase.co"
PUB = "sb_publishable_xqWRKqnOIKKqKgPJrdP5TA_GA7PCSiV"
GH = os.environ.get("GH_TOKEN", "")
RUN_SECONDS = int(os.environ.get("RUN_SECONDS", str(5 * 3600 + 20 * 60)))
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36 VYFRI-news"

FEEDS = [
    ("The Hacker News", "https://feeds.feedburner.com/TheHackersNews"),
    ("BleepingComputer", "https://www.bleepingcomputer.com/feed/"),
    ("SecurityWeek", "https://www.securityweek.com/feed/"),
    ("Krebs on Security", "https://krebsonsecurity.com/feed/"),
    ("Dark Reading", "https://www.darkreading.com/rss.xml"),
    ("The Record", "https://therecord.media/feed"),
    ("Help Net Security", "https://www.helpnetsecurity.com/feed/"),
    ("Infosecurity Magazine", "https://www.infosecurity-magazine.com/rss/news/"),
    ("WeLiveSecurity (ESET)", "https://www.welivesecurity.com/en/rss/feed/"),
    ("CISA", "https://www.cisa.gov/cybersecurity-advisories/all.xml"),
    ("Malwarebytes Labs", "https://www.malwarebytes.com/blog/feed/index.xml"),
    ("Sophos News", "https://news.sophos.com/en-us/feed/"),
    # تكنولوجيا عامة
    ("The Verge", "https://www.theverge.com/rss/index.xml"),
    ("TechCrunch", "https://techcrunch.com/feed/"),
    ("Ars Technica", "https://feeds.arstechnica.com/arstechnica/index"),
    ("Engadget", "https://www.engadget.com/rss.xml"),
    ("Wired", "https://www.wired.com/feed/rss"),
    ("9to5Google", "https://9to5google.com/feed/"),
    ("Android Authority", "https://www.androidauthority.com/feed/"),
    ("MIT Technology Review", "https://www.technologyreview.com/feed/"),
]


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def rpc(name, args, timeout=40):
    req = urllib.request.Request(
        f"{SB}/rest/v1/rpc/{name}", data=json.dumps(args).encode(),
        headers={"apikey": PUB, "Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read() or b"null")


# ---------------------------------------------------------------- الأخبار
def clean(s, limit):
    s = html.unescape(re.sub(r"<[^>]+>", " ", s or ""))
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"The post .{0,200} appeared first on .*$", "", s).strip()
    return s[:limit]


def parse_date(s):
    s = (s or "").strip()
    if not s:
        return None
    try:
        d = email.utils.parsedate_to_datetime(s)
    except Exception:  # noqa: BLE001
        try:
            d = datetime.fromisoformat(s.replace("Z", "+00:00"))
        except Exception:  # noqa: BLE001
            return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.astimezone(timezone.utc).isoformat()


def local(tag):
    return tag.rsplit("}", 1)[-1].lower()


def child_text(el, *names):
    for c in el:
        if local(c.tag) in names:
            if local(c.tag) == "link" and c.get("href"):
                if c.get("rel", "alternate") == "alternate":
                    return c.get("href")
                continue
            t = "".join(c.itertext())
            if t.strip():
                return t
    return ""


def fetch_feed(source, url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/rss+xml, application/xml, text/xml, */*"})
    with urllib.request.urlopen(req, timeout=25) as r:
        root = ET.fromstring(r.read())
    items = []
    for el in root.iter():
        if local(el.tag) not in ("item", "entry"):
            continue
        link = child_text(el, "link").strip()
        if not link:
            g = child_text(el, "guid").strip()
            link = g if g.startswith("http") else ""
        title = clean(child_text(el, "title"), 300)
        summary = clean(child_text(el, "description", "summary", "content", "encoded"), 1200)
        pub = parse_date(child_text(el, "pubdate", "published", "updated", "date"))
        if link.startswith("http") and title:
            items.append({"url": link, "title": title, "summary": summary, "source": source, "published": pub})
        if len(items) >= 12:
            break
    return items


def push_news():
    allitems = []
    for source, url in FEEDS:
        try:
            got = fetch_feed(source, url)
            allitems += got
            log(f"news: {source}: {len(got)}")
        except Exception as e:  # noqa: BLE001
            log(f"news: {source} failed: {str(e)[:120]}")
    if not allitems:
        return
    try:
        log("news stored:", rpc("ai_news_push", {"p_gh": GH, "p_items": allitems}, timeout=90))
    except Exception as e:  # noqa: BLE001
        log("news push failed:", str(e)[:200])


# ---------------------------------------------------------------- الصور
SAFE_PROMPT = ("A striking modern digital illustration about cybersecurity and online safety: a glowing shield with a "
               "padlock above a smartphone, network lines and data streams, cinematic lighting, deep navy, neon cyan and "
               "electric purple colors, square composition, highly detailed, no text, no letters, no logos.")


def openai_image(key, model, prompt, quality):
    body = {"model": model, "prompt": prompt, "size": "1024x1024", "quality": quality, "n": 1,
            "output_format": "jpeg", "output_compression": 85}
    req = urllib.request.Request("https://api.openai.com/v1/images/generations", data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                                 method="POST")
    with urllib.request.urlopen(req, timeout=240) as r:
        d = json.loads(r.read())["data"][0]
    if d.get("b64_json"):
        return base64.b64decode(d["b64_json"])
    with urllib.request.urlopen(urllib.request.Request(d["url"], headers={"User-Agent": UA}), timeout=60) as r:
        return r.read()


def cf_image(acc, tok, prompt):
    """صور مجانية من Cloudflare Workers AI (FLUX): الحد المجاني اليومي يكفي ~100 صورة."""
    base = f"https://api.cloudflare.com/client/v4/accounts/{acc}/ai/run/@cf/black-forest-labs/"
    hdr = {"Authorization": f"Bearer {tok}"}
    errs = []
    # 1) FLUX.2 klein: أوضح وأدق
    try:
        b = "----vyfri" + str(int(time.time() * 1000))
        parts = []
        for k, v in (("prompt", prompt[:2000]), ("width", "1024"), ("height", "1024")):
            parts.append(f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n')
        body = ("".join(parts) + f"--{b}--\r\n").encode()
        req = urllib.request.Request(base + "flux-2-klein-4b", data=body, method="POST",
                                     headers={**hdr, "Content-Type": f"multipart/form-data; boundary={b}"})
        with urllib.request.urlopen(req, timeout=180) as r:
            d = json.loads(r.read())
        img = (d.get("result") or d).get("image")
        if img:
            return base64.b64decode(img)
        errs.append("klein: empty")
    except Exception as e:  # noqa: BLE001
        errs.append("klein: " + http_err(e)[:150])
    # 2) FLUX.1 schnell احتياط
    try:
        req = urllib.request.Request(base + "flux-1-schnell", data=json.dumps({"prompt": prompt[:2000], "steps": 8}).encode(),
                                     method="POST", headers={**hdr, "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=180) as r:
            d = json.loads(r.read())
        img = (d.get("result") or d).get("image")
        if img:
            return base64.b64decode(img)
        errs.append("schnell: empty")
    except Exception as e:  # noqa: BLE001
        errs.append("schnell: " + http_err(e)[:150])
    raise RuntimeError(" | ".join(errs))


def http_err(e):
    if isinstance(e, urllib.error.HTTPError):
        try:
            return f"{e.code}: {e.read().decode(errors='replace')[:300]}"
        except Exception:  # noqa: BLE001
            return str(e.code)
    return str(e)[:300]


def make_image(job):
    data, err = None, None
    if job.get("key"):
        data, err = make_openai_image(job)
    cf = job.get("cf") or {}
    if data is None and cf.get("account") and cf.get("token"):
        log("using free Cloudflare images" + (f" (OpenAI: {str(err)[:80]})" if err else ""))
        for p in ((job.get("prompt") or SAFE_PROMPT), SAFE_PROMPT):
            try:
                return cf_image(cf["account"], cf["token"], p), None
            except Exception as e:  # noqa: BLE001
                err = ("Cloudflare: " + str(e))[:300]
                log("cf image failed:", err)
    return data, err


def make_openai_image(job):
    key, prompt = job["key"], (job.get("prompt") or SAFE_PROMPT)[:3500]
    quality = job.get("quality") or "medium"
    models = [job.get("model") or "gpt-image-2"]
    for m in ("gpt-image-2", "gpt-image-1-mini"):
        if m not in models:
            models.append(m)
    errs = []
    for model in models:
        for p in (prompt, SAFE_PROMPT):
            try:
                return openai_image(key, model, p, quality), None
            except Exception as e:  # noqa: BLE001
                msg = http_err(e)
                errs.append(f"{model}: {msg[:140]}")
                log("image failed:", model, msg[:200])
                low = msg.lower()
                if any(x in low for x in ("invalid_api_key", "incorrect api key", "billing", "insufficient_quota")):
                    return None, "OpenAI: " + msg[:200]   # مشكلة بالمفتاح/الرصيد: ما فائدة نعيد
                if p == prompt and ("safety" in low or "moderation" in low or "content_policy" in low):
                    continue        # الوصف انرفض: نجرب الوصف الآمن العام
                break               # غير هيج: نجرب النموذج الثاني
    return None, " | ".join(errs)[:300]


def upload(bucket, name, data):
    url = f"{SB}/storage/v1/object/{bucket}/{name}"
    for hdr in ({"apikey": PUB}, {"apikey": PUB, "Authorization": f"Bearer {PUB}"}):
        req = urllib.request.Request(url, data=data, method="POST",
                                     headers={**hdr, "Content-Type": "image/jpeg", "x-upsert": "false",
                                              "cache-control": "31536000"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return True, f"uploaded {r.status}"
        except Exception as e:  # noqa: BLE001
            last = http_err(e)
            log("upload failed:", last)
    return False, "upload " + last


def handle_images():
    for _ in range(3):
        job = rpc("ai_img_claim", {"p_gh": GH}, timeout=60)
        if not job:
            return
        log("image job", job["id"])
        data, err = make_image(job)
        ok = False
        if data:
            ok, err = upload(job.get("bucket", "posts"), job["name"], data)
        log("image done:", rpc("ai_img_done", {"p_gh": GH, "p_id": job["id"], "p_ok": ok, "p_info": None if ok else err}, timeout=60),
            "" if ok else err)


def main():
    if not GH:
        print("GH_TOKEN missing")
        sys.exit(1)
    start = time.time()
    last_news = 0.0
    while time.time() - start < RUN_SECONDS:
        if time.time() - last_news > 5 * 60:
            push_news()
            last_news = time.time()
        try:
            if rpc("ai_img_pending", {}):
                handle_images()
        except Exception as e:  # noqa: BLE001
            log("image loop error:", http_err(e))
        time.sleep(45)


if __name__ == "__main__":
    main()
