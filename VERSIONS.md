# Sidecar versions

The sender, pointer helper, bar widget and test tools are versioned with local Git commits and named tags. Installed copies are rebuilt from here with `./install.sh`. Nothing generated is committed.

| Tag | Date | State |
|---|---|---|
| `v0.1-wifi-usb-widget` | 2026-09-27 | First fully working build on a real iPad.<br>**Wi-Fi:** Bonjour. **USB:** built-in usbmuxd client; auto-prefers the cable, moves to it mid-session, falls back to Wi-Fi on unplug.<br>**x264:** no VBV, `level=5.1`, one slice, 10 s IDR; crf 18 on Wi-Fi, 15 on USB.<br>**Touch** input. **Widget** restyled like the built-in panels: on/off switch, USB/Wi-Fi badge, resolution/fps line, Bluetooth-style device rows.<br>**Debug:** `SIDECAR_DUMP`, `SIDECAR_X264`, `fake-receiver.py`, `fake-usbmuxd.py`. |

New tags are only for coherent checkpoints worth returning to, not every small edit.
