#!/bin/sh
set -e

DIR="${SIDEBOT_DIR:-/root/sidebot-local}"
BASE="https://github.com/Sideb0t/Sidebot/releases/latest/download"
PARTS="SideBot-v1.0.tar.gz.part0 SideBot-v1.0.tar.gz.part1"

if command -v apk >/dev/null 2>&1; then
  NEED=""
  command -v curl >/dev/null 2>&1 || NEED="$NEED curl ca-certificates"
  command -v tar >/dev/null 2>&1 || NEED="$NEED tar"
  [ -n "$NEED" ] && apk add --no-cache $NEED >/dev/null 2>&1 || true
fi

pkill -9 -f telegram_iloader_bot 2>/dev/null || true
pkill -9 -f ipatool 2>/dev/null || true

mkdir -p "$DIR"

TMPD="$(mktemp -d 2>/dev/null || echo "/tmp/sidebot.$$")"
mkdir -p "$TMPD"
trap 'rm -rf "$TMPD"' EXIT

FILES=""
i=0
for p in $PARTS; do
  i=$((i + 1))
  echo "⬇️ Downloading $p ..."
  if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar "$BASE/$p" -o "$TMPD/$i"
  else
    wget -O "$TMPD/$i" "$BASE/$p"
  fi
  FILES="$FILES $TMPD/$i"
done

echo "📦 Unpacking into $DIR ..."
cat $FILES | tar -xz -C "$DIR"

chmod +x "$DIR/start.sh" 2>/dev/null || true
echo "✅ SideBot installed to $DIR"

if [ -e /dev/tty ]; then
  exec sh "$DIR/start.sh" --local --bg "$@" < /dev/tty
else
  exec sh "$DIR/start.sh" --local --bg "$@"
fi
