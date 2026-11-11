#!/bin/bash
# install.sh - copy claude-credito into ~/.local/bin, its PATH shim into ~/.local/share/claude-credito/shim,
# and a starter config (every line commented out) into ~/.config/claude-credito/config if there is none.
# It stores no key: run `claude-credito --credit-store-key` after it.
#
#   ./install.sh [--dry-run]
#   ./install.sh --uninstall [--dry-run]     removes the two programs; keeps your config, key and log
#
# Environment: INSTALL_BIN_DIR (default ~/.local/bin), INSTALL_SHARE_DIR (default ~/.local/share/claude-credito).
set -u
R="$(cd "$(dirname "$0")" && pwd)"
BIN="${INSTALL_BIN_DIR:-$HOME/.local/bin}"
SHARE="${INSTALL_SHARE_DIR:-$HOME/.local/share/claude-credito}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/claude-credito/config"
DRY=0; UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

run() { if [ $DRY = 1 ]; then echo "(dry-run) $*"; else "$@"; fi; }

if [ $UNINSTALL = 1 ]; then
  for f in "$BIN/claude-credito" "$SHARE/shim/claude"; do
    [ -e "$f" ] && run rm -f "$f" && echo "removed $f"
  done
  [ $DRY = 1 ] || rmdir "$SHARE/shim" "$SHARE" 2>/dev/null
  echo "Kept: $CONF, your stored key and the log. Scripts that call claude-credito will fail until you point them back at claude."
  exit 0
fi

run mkdir -p "$BIN" "$SHARE/shim" "$(dirname "$CONF")"
# Each file is written next to its place and then renamed over it: a job that is running the old
# file right now keeps the old one (bash reads a script as it runs, so writing in place could break it).
if [ $DRY = 1 ]; then
  echo "(dry-run) write $BIN/claude-credito"
  echo "(dry-run) write $SHARE/shim/claude"
else
  cp "$R/bin/claude-credito" "$BIN/.claude-credito.new.$$" && chmod 755 "$BIN/.claude-credito.new.$$" \
    && mv -f "$BIN/.claude-credito.new.$$" "$BIN/claude-credito" || { echo "install.sh: could not write $BIN/claude-credito" >&2; exit 1; }
  # The shim runs the claude-credito installed above, wherever INSTALL_BIN_DIR put it.
  sed "s|@CLAUDE_CREDITO@|$BIN/claude-credito|" "$R/shim/claude" > "$SHARE/shim/.claude.new.$$" && chmod 755 "$SHARE/shim/.claude.new.$$" \
    && mv -f "$SHARE/shim/.claude.new.$$" "$SHARE/shim/claude" || { echo "install.sh: could not write $SHARE/shim/claude" >&2; exit 1; }
fi
echo "installed $BIN/claude-credito"
echo "installed $SHARE/shim/claude"
if [ -e "$CONF" ]; then
  echo "kept your config: $CONF"
else
  run cp "$R/config.example" "$CONF" && echo "wrote a starter config (changes nothing until you edit it): $CONF"
fi
case ":$PATH:" in *":$BIN:"*) ;; *) echo "note: $BIN is not on your PATH; call claude-credito by its full path" ;; esac
echo "Next: claude-credito --credit-store-key   (then: claude-credito --credit-status)"
