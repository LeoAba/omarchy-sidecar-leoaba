#!/usr/bin/env bash
# Install omarchy-sidecar from this folder (the vault copy is canonical).
#   ./install.sh            build + install CLI, pointer helper and bar plugin
#   ./install.sh --bar      also place the widget on the bar (before the monitor widget)
#   ./install.sh --uninstall
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin/omarchy-sidecar"
LIB="$HOME/.local/lib/omarchy-sidecar"
PLUGIN="$HOME/.config/omarchy/plugins/leoaba.sidecar"

if [[ "${1:-}" == "--uninstall" ]]; then
  "$BIN" stop 2>/dev/null || true
  python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home() / ".config/omarchy/shell.json"
c = json.loads(p.read_text())
for sec, items in c.get("bar", {}).get("layout", {}).items():
    c["bar"]["layout"][sec] = [w for w in items if w.get("id") != "leoaba.sidecar"]
p.write_text(json.dumps(c, indent=2) + "\n")
PY
  rm -rf "$BIN" "$LIB" "$PLUGIN"
  echo "uninstalled"
  exit 0
fi

need=()
for p in wf-recorder avahi-browse wayland-scanner cc; do command -v "$p" >/dev/null || need+=("$p"); done
((${#need[@]})) && { echo "missing: ${need[*]} (pacman: wf-recorder avahi wayland gcc)"; exit 1; }

# Build the pointer helper out of tree (keeps generated files out of the vault).
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
cp "$SRC"/pointer/{Makefile,sidecar-pointer.c,wlr-virtual-pointer-unstable-v1.xml} "$build"/
make -s -C "$build"
install -Dm755 "$build/sidecar-pointer" "$LIB/sidecar-pointer"

install -Dm755 "$SRC/omarchy-sidecar" "$BIN"
mkdir -p "$PLUGIN"
install -m644 "$SRC"/plugin/{manifest.json,Panel.qml} "$PLUGIN"/

if [[ "${1:-}" == "--bar" ]]; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true; sleep 1
  cp ~/.config/omarchy/shell.json ~/.config/omarchy/shell.json.bak.$(date +%s)
  omarchy bar put leoaba.sidecar --before omarchy.monitor
fi
echo "installed: $BIN, $LIB/sidecar-pointer, $PLUGIN"
