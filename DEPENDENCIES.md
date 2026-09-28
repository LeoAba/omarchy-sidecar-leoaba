# Dependencies

Everything Sidecar - leoaba uses, and the versions it was tested with on 2026-09-28: Omarchy 4.0.3rc4 on Arch Linux ARM (Asahi kernel 7.1.13), on a 13" M1 MacBook Pro (MacBookPro17,1).

## Runtime (required)

| Package | Tested version | Used for |
|---|---|---|
| hyprland | 0.56.2-3 | Virtual monitor (`hyprctl output create headless`), Lua `hl.monitor` / `hl.dsp.cursor.move`, screencopy |
| quickshell | 0.3.1-1 | The bar widget (Omarchy shell) |
| wf-recorder | 0.6.0-2 | Captures the virtual monitor (wlr-screencopy) and encodes it |
| ffmpeg | 9.0.2-1 | Used by wf-recorder (libx264 encoder, scaling) |
| x264 | 0.165.r3222 | H.264 encoder library |
| avahi | 0.9rc5-1 | Finds the iPad on the network (`avahi-browse`, Bonjour `_opensidecar._tcp`) |
| python | 3.14.7-1 | The sender (`bin/omarchy-sidecar`), standard library only |
| wayland | 1.26.0-1 | `wayland-client` and `wayland-scanner`, to build the touch helper |

## Build (the touch helper, built once by `setup`)

| Package | Tested version |
|---|---|
| gcc | 16.1.1 |
| make | 4.4.1-3 |
| pkgconf | 3.0.7-1 |

## Optional

| Package | Tested version | Used for |
|---|---|---|
| usbmuxd | 1.1.1-4 | USB connection to the iPad. Install, replug the iPad, tap **Trust** |
| jq, rsync | 1.8.2, 3.5.1 | Only for the developer script `install.sh` |

## On the iPad

| App | Notes |
|---|---|
| [OpenDisplay](https://github.com/peetzweg/opendisplay) | Free, via [TestFlight](https://testflight.apple.com/join/3NYaY11c). GPL-3.0, a separate project. Tested with protocol version 3 on an 11" iPad Pro (2388×1668). |

`setup` checks for the required and build packages and reports any that are missing. It never installs packages itself.
