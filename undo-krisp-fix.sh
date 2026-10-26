#!/bin/bash
# Puts back Discord's original Krisp module and Renderer helper.
# Quit Discord, then run: sudo ./undo-krisp-fix.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME="$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory | awk '{print $2}')"
SUPPORT="$USER_HOME/Library/Application Support/discord"
RENDERER="/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app"
BACKUPS="$HERE/originals"

if pgrep -xq Discord; then
  echo "Quit Discord first." >&2
  exit 1
fi

shopt -s nullglob
for backup in "$BACKUPS"/*.discord_krisp.node; do
  tag="$(basename "$backup" .discord_krisp.node)"
  node="$SUPPORT/${tag%%_discord_krisp-*}/modules/discord_krisp-${tag##*_discord_krisp-}/discord_krisp/discord_krisp.node"
  if [ -f "$node" ]; then
    cp -p "$backup" "$node"
    echo "Restored $tag"
  fi
done

if [ -d "$BACKUPS/Discord Helper (Renderer).app" ]; then
  rm -rf "$RENDERER"
  cp -Rp "$BACKUPS/Discord Helper (Renderer).app" "$RENDERER"
  echo "Restored Renderer helper"
fi

echo "Done. If Discord still misbehaves, reinstall it from discord.com."
