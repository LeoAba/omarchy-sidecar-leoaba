#!/usr/bin/env bash
# Developer install: copy this working tree into the plugin folder, the same
# place `omarchy plugin add` puts it, then run ./setup there.
#   ./install.sh            install/update (migrates the old leoaba.sidecar id)
#   ./install.sh --bar      also place the widget on the bar (before the monitor widget)
#   ./install.sh --uninstall
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
ID="io.github.leoaba.sidecar"
DEST="$HOME/.config/omarchy/plugins/$ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

if [[ ${1:-} == --uninstall ]]; then
  [[ -x $DEST/setup ]] && "$DEST/setup" --uninstall
  omarchy plugin remove "$ID" --yes 2>/dev/null || rm -rf "$DEST"
  exit 0
fi

# One-time migration from the old id and install layout.
OLD="$HOME/.config/omarchy/plugins/leoaba.sidecar"
if [[ -d $OLD || -e $HOME/.local/lib/omarchy-sidecar ]]; then
  [[ -x $HOME/.local/bin/omarchy-sidecar ]] && "$HOME/.local/bin/omarchy-sidecar" stop >/dev/null 2>&1 || true
  rm -rf "$OLD" "$HOME/.local/lib/omarchy-sidecar"
  [[ -f $HOME/.local/bin/omarchy-sidecar && ! -L $HOME/.local/bin/omarchy-sidecar ]] && rm -f "$HOME/.local/bin/omarchy-sidecar"
  if [[ -f $SHELL_JSON ]] && grep -q '"leoaba.sidecar"' "$SHELL_JSON"; then
    cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
    tmp=$(mktemp); jq --arg id "$ID" '(.. | objects | select(.id? == "leoaba.sidecar") | .id) = $id' "$SHELL_JSON" > "$tmp" && mv "$tmp" "$SHELL_JSON"
  fi
  echo "migrated leoaba.sidecar -> $ID"
fi

mkdir -p "$DEST"
rsync -a --delete --exclude .git --exclude '__pycache__' \
  --exclude 'pointer/sidecar-pointer' --exclude 'pointer/*-protocol.c' --exclude 'pointer/*-client-protocol.h' \
  "$SRC"/ "$DEST"/
"$DEST/setup" >/dev/null

if [[ ${1:-} == --bar ]]; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true; sleep 1
  cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
  omarchy bar put "$ID" --before omarchy.monitor
fi
echo "installed: $DEST (CLI: ~/.local/bin/omarchy-sidecar)"
