"""اختبار بسيط لخوادم TURN: يطلب حجز (Allocate) ويطبع النتيجة.

الاستخدام: python3 turn_test.py host port udp|tcp username password
"""
import hashlib
import hmac
import os
import socket
import struct
import sys

MAGIC = 0x2112A442


def attr(t, v):
    pad = (4 - len(v) % 4) % 4
    return struct.pack("!HH", t, len(v)) + v + b"\0" * pad


def msg(mtype, attrs, key=None):
    tid = os.urandom(12)
    body = b"".join(attrs)
    if key is not None:
        # MESSAGE-INTEGRITY يُحسب على الرسالة مع طول يشمل الخاصية نفسها (24 بايت)
        hdr = struct.pack("!HHI", mtype, len(body) + 24, MAGIC) + tid
        mac = hmac.new(key, hdr + body, hashlib.sha1).digest()
        body += attr(0x0008, mac)
    return struct.pack("!HHI", mtype, len(body), MAGIC) + tid + body


def parse(data):
    mtype, length, _ = struct.unpack("!HHI", data[:8])
    attrs, i = {}, 20
    while i < 20 + length:
        t, l = struct.unpack("!HH", data[i:i + 4])
        attrs[t] = data[i + 4:i + 4 + l]
        i += 4 + l + ((4 - l % 4) % 4)
    return mtype, attrs


def exchange(sock, proto, packet, addr):
    if proto == "udp":
        sock.sendto(packet, addr)
        return sock.recvfrom(4096)[0]
    sock.sendall(packet)
    head = sock.recv(20)
    length = struct.unpack("!H", head[2:4])[0]
    rest = b""
    while len(rest) < length:
        rest += sock.recv(length - len(rest))
    return head + rest


def main():
    host, port, proto, user, pwd = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
    addr = (socket.gethostbyname(host), port)
    if proto == "udp":
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    else:
        s = socket.create_connection(addr, timeout=8)
    s.settimeout(8)
    transport = attr(0x0019, bytes([17 if proto == "udp" else 6, 0, 0, 0]))
    # الطلب الأول بدون مصادقة: الخادم يرد 401 مع realm و nonce
    mtype, a = parse(exchange(s, proto, msg(0x0003, [attr(0x0019, bytes([17, 0, 0, 0]))]), addr))
    if 0x0014 not in a:
        print("RESULT", host, port, proto, "no realm (type 0x%04x)" % mtype)
        return
    realm, nonce = a[0x0014], a[0x0015]
    key = hashlib.md5(user.encode() + b":" + realm + b":" + pwd.encode()).digest()
    attrs = [attr(0x0019, bytes([17, 0, 0, 0])), attr(0x0006, user.encode()), attr(0x0014, realm), attr(0x0015, nonce)]
    mtype, a = parse(exchange(s, proto, msg(0x0003, attrs, key), addr))
    if mtype == 0x0103:
        print("RESULT", host, port, proto, "ALLOCATE OK ✅")
    else:
        code = a.get(0x0009, b"")
        err = (code[2] * 100 + code[3]) if len(code) >= 4 else "?"
        print("RESULT", host, port, proto, "FAILED error", err, code[4:].decode(errors="ignore"))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        print("RESULT", sys.argv[1], sys.argv[2], sys.argv[3], "EXCEPTION", e)
