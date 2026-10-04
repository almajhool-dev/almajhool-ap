"""يحذف مكتبات نوع معالج معيّن من ملف APK (للنسخ المصغّرة). الاستخدام: strip_abi.py in.apk abi out.apk"""
import sys, zipfile

src, drop, out = sys.argv[1], sys.argv[2], sys.argv[3]
with zipfile.ZipFile(src) as zin, zipfile.ZipFile(out, "w") as zout:
    for info in zin.infolist():
        n = info.filename
        if n.startswith("lib/" + drop + "/"):
            continue
        # التوقيع القديم ينشال (ينعاد التوقيع بعدين)
        if n.startswith("META-INF/") and n.rsplit(".", 1)[-1].upper() in ("SF", "RSA", "EC", "DSA", "MF"):
            continue
        data = zin.read(n)
        zi = zipfile.ZipInfo(n, date_time=info.date_time)
        zi.compress_type = info.compress_type
        zi.external_attr = info.external_attr
        zout.writestr(zi, data)
