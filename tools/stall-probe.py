#!/usr/bin/env python3
"""Watch for desktop stalls while testing the sidecar (e.g. the long-session
Hyprland screencopy bug). Pings Hyprland's IPC socket every 20 ms and the
Omarchy shell every 250 ms, and logs any Hyprland reply over 100 ms or shell
reply over 400 ms with a timestamp. Match the times against sidecar.log's
`teardown ... remove ...ms` lines.

  stall-probe.py [MINUTES=10] [LOGFILE=stalls.log]
"""
import os, sys, time, socket, subprocess, threading
sig = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]; path = f"{os.environ['XDG_RUNTIME_DIR']}/hypr/{sig}/.socket.sock"
minutes = float(sys.argv[1]) if len(sys.argv) > 1 else 10
log = open(sys.argv[2] if len(sys.argv) > 2 else "stalls.log", "a", buffering=1)
end = time.time() + minutes * 60
def hypr():
    while time.time() < end:
        t = time.time()
        try:
            s = socket.socket(socket.AF_UNIX); s.settimeout(10); s.connect(path); s.sendall(b"j/monitors"); s.recv(1 << 20); s.close()
        except OSError as e:
            log.write(f"{time.strftime('%H:%M:%S')} hyprland error {e}\n")
        ms = (time.time() - t) * 1000
        if ms > 100: log.write(f"{time.strftime('%H:%M:%S', time.localtime(t))} HYPRLAND stall {ms:.0f} ms\n")
        time.sleep(0.02)
def shell():
    while time.time() < end:
        t = time.time()
        subprocess.run(["omarchy-shell", "sidecar", "status"], capture_output=True, timeout=30)
        ms = (time.time() - t) * 1000
        if ms > 400: log.write(f"{time.strftime('%H:%M:%S', time.localtime(t))} SHELL slow {ms:.0f} ms\n")
        time.sleep(0.25)
log.write(f"{time.strftime('%H:%M:%S')} probe start\n")
a = threading.Thread(target=hypr); b = threading.Thread(target=shell); a.start(); b.start(); a.join(); b.join()
log.write(f"{time.strftime('%H:%M:%S')} probe end\n")
