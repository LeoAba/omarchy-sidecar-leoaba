#!/usr/bin/env python3
"""Stand-in for usbmuxd with one "cabled" iPad, for testing the USB path of
omarchy-sidecar without a cable.

Serves the usbmuxd plist protocol on a unix socket. ListDevices reports one
USB device; Connect to its port 9000 is forwarded to --target (a fake
receiver, or the real iPad over Wi-Fi), then bytes are spliced both ways.
Touch --unplug FILE (or wait --unplug-after seconds) to make the device
vanish and drop its connections, like pulling the cable.

  fake-usbmuxd.py --socket /tmp/usbmuxd --target 127.0.0.1:9000 [--plug-after 0] [--unplug-after 0]
  USBMUXD_SOCKET_ADDRESS=/tmp/usbmuxd omarchy-sidecar connect
"""
import argparse, os, plistlib, select, socket, struct, threading, time

ap = argparse.ArgumentParser()
ap.add_argument("--socket", required=True)
ap.add_argument("--target", default="127.0.0.1:9000")
ap.add_argument("--plug-after", type=float, default=0, help="report no device until then")
ap.add_argument("--unplug-after", type=float, default=0, help="then report none again and cut links")
a = ap.parse_args()
host, port = a.target.rsplit(":", 1)
t0 = time.time()
links = []


def plugged():
    t = time.time() - t0
    return t >= a.plug_after and not (a.unplug_after and t >= a.unplug_after)


def reply(conn, tag, msg):
    body = plistlib.dumps(msg)
    conn.sendall(struct.pack("<IIII", 16 + len(body), 1, 8, tag) + body)


def splice(x, y):
    links.append((x, y))
    try:
        while True:
            r, _, _ = select.select([x, y], [], [], 0.2)
            if not plugged():
                break
            for s in r:
                data = s.recv(1 << 16)
                if not data:
                    return
                (y if s is x else x).sendall(data)
    except OSError:
        pass
    finally:
        for s in (x, y):
            try:
                s.close()
            except OSError:
                pass
        print("link closed", flush=True)


def client(conn):
    head = conn.recv(16)
    if len(head) < 16:
        conn.close()
        return
    n, _, _, tag = struct.unpack("<IIII", head)
    body = b""
    while len(body) < n - 16:
        body += conn.recv(n - 16 - len(body))
    msg = plistlib.loads(body)
    kind = msg.get("MessageType")
    if kind == "ListDevices":
        devs = [{"DeviceID": 7, "MessageType": "Attached",
                 "Properties": {"ConnectionType": "USB", "DeviceID": 7, "SerialNumber": "FAKE-IPAD"}}]
        reply(conn, tag, {"DeviceList": devs if plugged() else []})
        conn.close()
    elif kind == "Connect":
        want = socket.ntohs(msg["PortNumber"])
        try:
            if not plugged() or msg["DeviceID"] != 7 or want != 9000:
                raise OSError("no such device/port")
            up = socket.create_connection((host, int(port)), timeout=3)
        except OSError:
            reply(conn, tag, {"MessageType": "Result", "Number": 3})
            conn.close()
            return
        reply(conn, tag, {"MessageType": "Result", "Number": 0})
        print("USB link up ->", a.target, flush=True)
        splice(conn, up)
    else:
        reply(conn, tag, {"MessageType": "Result", "Number": 1})
        conn.close()


if os.path.exists(a.socket):
    os.unlink(a.socket)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(a.socket)
srv.listen(8)
print("fake usbmuxd on", a.socket, flush=True)
try:
    while True:
        c, _ = srv.accept()
        threading.Thread(target=client, args=(c,), daemon=True).start()
except KeyboardInterrupt:
    pass
finally:
    os.unlink(a.socket)
