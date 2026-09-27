#!/usr/bin/env python3
"""Stand-in for the OpenDisplay iPad app, for testing omarchy-sidecar without an iPad.

Listens on TCP 9000, advertises _opensidecar._tcp via avahi-publish, sends
hello/ping like the real receiver, and writes the received H.264 to a file
while checking the wire rules (4-byte start codes, SPS/PPS on every IDR,
IDR first). Optionally sends kf / rotation hello / closing on a schedule.

  fake-receiver.py [--seconds 8] [--out received.h264] [--rotate-at 4] [--kf-at 3]
"""
import argparse, json, os, re, socket, struct, subprocess, sys, threading, time, uuid

ap = argparse.ArgumentParser()
ap.add_argument("--port", type=int, default=9000)
ap.add_argument("--seconds", type=float, default=8)
ap.add_argument("--out", default="received.h264")
ap.add_argument("--size", default="2360x1640")
ap.add_argument("--kf-at", type=float, default=0)
ap.add_argument("--rotate-at", type=float, default=0)
ap.add_argument("--touch-at", type=float, default=0, help="send one tap (moves the real cursor!)")
ap.add_argument("--no-publish", action="store_true")
a = ap.parse_args()

W, H = map(int, a.size.split("x"))
dev_id = str(uuid.uuid4())
pub = None
if not a.no_publish:
    pub = subprocess.Popen(["avahi-publish", "-s", "Fake iPad", "_opensidecar._tcp", str(a.port),
                            f"id={dev_id}", "pv=3"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("0.0.0.0", a.port))
srv.listen(1)
srv.settimeout(30)
print("fake receiver listening on", a.port, flush=True)
conn, peer = srv.accept()
conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
print("sender connected from", peer, flush=True)
lock = threading.Lock()

def send(msg):
    p = json.dumps(msg).encode()
    with lock:
        conn.sendall(struct.pack(">I", len(p)) + p)

send({"type": "hello", "pixelsWide": W, "pixelsHigh": H, "scale": 2, "device": "iPad", "id": dev_id, "pv": 3})
t0 = time.time()
stats = {"frames": 0, "idr": 0, "bytes": 0, "ctrl": {}, "errors": [], "lat": [], "first_is_idr": None}
out = open(a.out, "wb")
done = threading.Event()

def schedule():
    fired = set()
    while not done.is_set():
        el = time.time() - t0
        send({"type": "ping", "t": int(time.time() * 1000)})
        if a.kf_at and el >= a.kf_at and "kf" not in fired:
            fired.add("kf"); send({"type": "kf"}); print("-> kf", flush=True)
        if a.rotate_at and el >= a.rotate_at and "rot" not in fired:
            fired.add("rot"); send({"type": "hello", "pixelsWide": H, "pixelsHigh": W, "scale": 2, "id": dev_id, "pv": 3})
            print("-> rotated hello", flush=True)
        if a.touch_at and el >= a.touch_at and "touch" not in fired:
            fired.add("touch")
            send({"type": "touch", "phase": "began", "x": 0.5, "y": 0.5}); send({"type": "touch", "phase": "ended", "x": 0.5, "y": 0.5})
            print("-> tap", flush=True)
        if el >= a.seconds:
            send({"type": "closing"}); done.set(); break
        time.sleep(0.5)

threading.Thread(target=schedule, daemon=True).start()
buf = b""
conn.settimeout(1)
while not (done.is_set() and time.time() - t0 > a.seconds + 0.5):
    try:
        chunk = conn.recv(1 << 20)
    except socket.timeout:
        continue
    except OSError:
        break
    if not chunk:
        break
    buf += chunk
    while len(buf) >= 4:
        n = struct.unpack(">I", buf[:4])[0]
        if len(buf) < 4 + n:
            break
        p, buf = buf[4:4 + n], buf[4 + n:]
        if n < 32768 and p[:1] == b"{" and b"\0" not in p:
            t = json.loads(p).get("type")
            stats["ctrl"][t] = stats["ctrl"].get(t, 0) + 1
            continue
        i = p.find(b"\0\0\0\1")
        if i > 0:
            tele = json.loads(p[:i]); stats["lat"].append(time.time() * 1000 - tele["cap"])
        video = p[i:]
        types = [video[m.end()] & 0x1F for m in re.finditer(b"\0\0\0\1", video)]
        n3 = len(re.findall(b"(?<!\0)\0\0\1", video))
        if n3:
            stats["errors"].append("3-byte start code")
        idr = 5 in types
        if stats["first_is_idr"] is None:
            stats["first_is_idr"] = idr
        if idr and not (7 in types and 8 in types):
            stats["errors"].append("IDR without SPS/PPS")
        stats["frames"] += 1; stats["idr"] += idr; stats["bytes"] += len(video)
        out.write(video)

out.close(); conn.close()
if pub: pub.terminate()
lat = sorted(stats["lat"])
print(json.dumps({
    "frames": stats["frames"], "idr": stats["idr"], "MB": round(stats["bytes"] / 1e6, 2),
    "first_is_idr": stats["first_is_idr"], "control": stats["ctrl"],
    "errors": sorted(set(stats["errors"])),
    "latency_ms_p50": round(lat[len(lat) // 2]) if lat else None,
    "latency_ms_p95": round(lat[int(len(lat) * .95)]) if lat else None,
}, indent=2))
