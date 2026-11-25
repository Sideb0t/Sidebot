#!/bin/sh
set -e

DIR="${SIDEBOT_DIR:-/root/telegram-iloader-minis}"
URL="https://github.com/Vitaliicloud/SideBot/releases/latest/download/SideBot-v1.0.tar.gz"

if command -v apk >/dev/null 2>&1; then
  NEED=""
  command -v curl >/dev/null 2>&1 || NEED="$NEED curl ca-certificates"
  command -v tar >/dev/null 2>&1 || NEED="$NEED tar"
  [ -n "$NEED" ] && apk add --no-cache $NEED >/dev/null 2>&1 || true
fi

pkill -9 -f telegram_iloader_bot 2>/dev/null || true
pkill -9 -f ipatool 2>/dev/null || true

mkdir -p "$DIR"
echo "⬇️ Downloading SideBot into $DIR ..."
if command -v curl >/dev/null 2>&1; then
  curl -fL --progress-bar "$URL" | tar -xz -C "$DIR"
else
  wget -O- "$URL" | tar -xz -C "$DIR"
fi

chmod +x "$DIR/start.sh" 2>/dev/null || true
echo "✅ SideBot installed to $DIR"

if [ -e /dev/tty ]; then
  exec sh "$DIR/start.sh" "$@" < /dev/tty
else
  exec sh "$DIR/start.sh" "$@"
fi
