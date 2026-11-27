#!/bin/sh
set -e

DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$DIR"
export GOMAXPROCS=1
export GOGC=40

# 1. Install Alpine dependencies if running in Open Minis / Alpine
if command -v apk >/dev/null 2>&1; then
  NEED_APK=""
  command -v python3 >/dev/null 2>&1 || NEED_APK="$NEED_APK python3"
  command -v openssl >/dev/null 2>&1 || NEED_APK="$NEED_APK openssl"
  command -v ssh >/dev/null 2>&1 || NEED_APK="$NEED_APK openssh-client"
  command -v curl >/dev/null 2>&1 || NEED_APK="$NEED_APK curl ca-certificates"
  [ -e /lib/ld-linux-aarch64.so.1 ] || NEED_APK="$NEED_APK gcompat"
  if [ -n "$NEED_APK" ]; then
    echo "📦 Installing packages:$NEED_APK ..."
    apk update >/dev/null 2>&1 || true
    apk add --no-cache $NEED_APK libstdc++ >/dev/null 2>&1 || apk add --no-cache $NEED_APK
  fi
fi

# 2. Ensure executable bit on bundled binaries
for bin in zsign ipatool siboot sideloader install-helper/target/release/telegram-iloader-install; do
  [ -f "$DIR/$bin" ] && chmod +x "$DIR/$bin" 2>/dev/null || true
done

# 2b. CLI sideload mode: `./start.sh --ipa /path/to/app.ipa`
if [ "${1:-}" = "--ipa" ]; then
  shift
  IPA_PATH="${1:-}"
  [ -n "$IPA_PATH" ] || { echo "Usage: $0 --ipa /path/to/app.ipa [--apple-id email]"; exit 1; }
  shift || true
  exec python3 "$DIR/telegram_iloader_bot.py" --ipa "$IPA_PATH" "$@"
fi

# 2c. Parse --local / --bg flags
LOCAL_FLAG=0
BG_FLAG=0
for _arg in "$@"; do
  case "$_arg" in
    --local) LOCAL_FLAG=1 ;;
    --bg) BG_FLAG=1 ;;
  esac
done

# 3. Read existing .env if present
ENV_FILE="$DIR/.env"
BOT_TOKEN=""
OWNER_ID=""
LOCAL_ONLY=""
if [ -f "$ENV_FILE" ]; then
  BOT_TOKEN="$(grep -E '^BOT_TOKEN=' "$ENV_FILE" | head -n1 | cut -d= -f2- | tr -d '"\r' | xargs || true)"
  OWNER_ID="$(grep -E '^OWNER_ID=' "$ENV_FILE" | head -n1 | cut -d= -f2- | tr -d '"\r' | xargs || true)"
  LOCAL_ONLY="$(grep -E '^LOCAL_ONLY=' "$ENV_FILE" | head -n1 | cut -d= -f2- | tr -d '"\r' | xargs || true)"
fi

if [ "$LOCAL_FLAG" = "1" ]; then
  LOCAL_ONLY="1"
  if [ ! -f "$ENV_FILE" ]; then
    {
      printf 'LOCAL_ONLY=1\n'
      printf 'OWNER_ID=1\n'
      printf 'MINIS_MODE=1\n'
      printf 'P12_PASSWORD=1\n'
      printf 'OTA_PORT=8080\n'
    } > "$ENV_FILE"
  elif ! grep -q '^LOCAL_ONLY=' "$ENV_FILE" 2>/dev/null; then
    printf 'LOCAL_ONLY=1\n' >> "$ENV_FILE"
  fi
fi

# 4. First-run interactive setup wizard (with language + mode selection)
if [ "$LOCAL_ONLY" != "1" ] && { [ -z "$BOT_TOKEN" ] || [ -z "$OWNER_ID" ]; }; then
  echo ""
  echo "=================================================="
  echo "  🚀 SideBot — First-time Setup"
  echo "=================================================="
  echo ""
  echo "🌐 Choose language / Обери мову / Выбери язык / Sprache:"
  echo "  1) Українська (uk)"
  echo "  2) Русский (ru)"
  echo "  3) English (en)"
  echo "  4) Deutsch (de)"
  printf "Select [1-4, default 1]: "
  IFS= read -r LANG_CHOICE || LANG_CHOICE="1"
  LANG_CHOICE="$(printf '%s' "$LANG_CHOICE" | tr -d ' \r\n\t')"
  case "$LANG_CHOICE" in
    2|ru) SEL_LANG="ru" ;;
    3|en) SEL_LANG="en" ;;
    4|de) SEL_LANG="de" ;;
    *) SEL_LANG="uk" ;;
  esac
  printf '{"lang": "%s"}\n' "$SEL_LANG" > "$DIR/language.json"

  echo ""
  echo "Mode / Режим:"
  echo "  1) Local only (без Telegram — відкрити http://127.0.0.1:8080/miniapp.html в Safari)"
  echo "  2) Telegram Bot (потрібен BOT_TOKEN і OWNER_ID)"
  printf "Select [1-2, default 1]: "
  IFS= read -r MODE_CHOICE || MODE_CHOICE="1"
  MODE_CHOICE="$(printf '%s' "$MODE_CHOICE" | tr -d ' \r\n\t')"
  if [ "$MODE_CHOICE" != "2" ]; then
    {
      printf 'LOCAL_ONLY=1\n'
      printf 'OWNER_ID=1\n'
      printf 'MINIS_MODE=1\n'
      printf 'P12_PASSWORD=1\n'
      printf 'OTA_PORT=8080\n'
    } > "$ENV_FILE"
    LOCAL_ONLY="1"
    echo ""
    echo "✅ Local mode saved to .env (lang: $SEL_LANG)."
    echo "   Open in Safari: http://127.0.0.1:8080/miniapp.html"
    echo ""
  else
  echo ""
  case "$SEL_LANG" in
    ru)
      echo "Чтобы бот заработал, сделай 2 быстрых шага в Telegram:"
      echo "  1) Создай бота в @BotFather (https://t.me/BotFather):"
      echo "     • Отправь /newbot, введи имя и @username"
      echo "     • Скопируй HTTP API Token (вида 1234567890:AAH...)"
      echo "  2) Узнай свой числовой OWNER_ID в @userinfobot (https://t.me/userinfobot):"
      echo "     • Нажми Start и скопируй число из поля Id"
      ;;
    en)
      echo "Complete 2 quick steps in Telegram to start the bot:"
      echo "  1) Create a bot via @BotFather (https://t.me/BotFather):"
      echo "     • Send /newbot, pick a name and @username"
      echo "     • Copy the HTTP API Token (like 1234567890:AAH...)"
      echo "  2) Get your numeric OWNER_ID via @userinfobot (https://t.me/userinfobot):"
      echo "     • Tap Start and copy the number from Id"
      ;;
    de)
      echo "2 kurze Schritte in Telegram, um den Bot zu starten:"
      echo "  1) Bot über @BotFather erstellen (https://t.me/BotFather):"
      echo "     • /newbot senden, Namen und @username wählen"
      echo "     • HTTP API Token kopieren (z.B. 1234567890:AAH...)"
      echo "  2) Deine numerische OWNER_ID über @userinfobot holen (https://t.me/userinfobot):"
      echo "     • Start tippen und die Zahl bei Id kopieren"
      ;;
    *)
      echo "Щоб бот запрацював, зроби 2 швидкі кроки в Telegram:"
      echo "  1) Створи бота в @BotFather (https://t.me/BotFather):"
      echo "     • Надішли /newbot, введи назву та @username"
      echo "     • Скопіюй HTTP API Token (вигляду 1234567890:AAH...)"
      echo "  2) Дізнайся свій числовий OWNER_ID у @userinfobot (https://t.me/userinfobot):"
      echo "     • Натисни Start і скопіюй число з поля Id"
      ;;
  esac
  echo "--------------------------------------------------"

  while [ -z "$BOT_TOKEN" ]; do
    printf "BOT_TOKEN: "
    IFS= read -r INPUT_TOKEN || exit 1
    INPUT_TOKEN="$(printf '%s' "$INPUT_TOKEN" | tr -d ' \r\n\t')"
    case "$INPUT_TOKEN" in
      *:*)
        BOT_TOKEN="$INPUT_TOKEN"
        ;;
      *)
        echo "❌ Invalid token (must contain ':'). Try again."
        ;;
    esac
  done

  while [ -z "$OWNER_ID" ]; do
    printf "OWNER_ID (digits only): "
    IFS= read -r INPUT_ID || exit 1
    INPUT_ID="$(printf '%s' "$INPUT_ID" | tr -d ' \r\n\t')"
    case "$INPUT_ID" in
      ''|*[!0-9]*)
        echo "❌ OWNER_ID must be digits only. Try again."
        ;;
      *)
        OWNER_ID="$INPUT_ID"
        ;;
    esac
  done

  {
    printf 'BOT_TOKEN=%s\n' "$BOT_TOKEN"
    printf 'OWNER_ID=%s\n' "$OWNER_ID"
    printf 'MINIS_MODE=1\n'
    printf 'P12_PASSWORD=1\n'
    printf 'OTA_PORT=8080\n'
  } > "$ENV_FILE"

  echo ""
  echo "✅ Saved to .env (lang: $SEL_LANG). Open your bot in Telegram and send /start!"
  echo ""
  fi
fi

grep -q '^P12_PASSWORD=' "$ENV_FILE" 2>/dev/null || printf 'P12_PASSWORD=1\n' >> "$ENV_FILE"
grep -q '^OTA_PORT=' "$ENV_FILE" 2>/dev/null || printf 'OTA_PORT=8080\n' >> "$ENV_FILE"

pkill -9 -f telegram_iloader_bot.py 2>/dev/null || true
sleep 0.3
for _rc in "$HOME/.profile" "$HOME/.ashrc" "$HOME/.bashrc"; do
  [ -f "$_rc" ] || touch "$_rc" 2>/dev/null || true
  grep -q 'alias sb=' "$_rc" 2>/dev/null || printf '\nalias sb="%s/start.sh --local --bg"\n' "$DIR" >> "$_rc" 2>/dev/null || true
done
for _bd in /usr/local/bin /usr/bin; do
  mkdir -p "$_bd" 2>/dev/null || true
  printf '#!/bin/sh\nexec "%s/start.sh" --local --bg "$@"\n' "$DIR" > "$_bd/sb" 2>/dev/null && chmod +x "$_bd/sb" 2>/dev/null || true
done
BOT_ARGS=""
[ "$LOCAL_FLAG" = "1" ] && BOT_ARGS="--local"
if [ "$BG_FLAG" = "1" ]; then
  nohup python3 "$DIR/telegram_iloader_bot.py" $BOT_ARGS >> /tmp/bot.log 2>&1 &
  _PID=$!
  _VER="$(python3 -c 'import json;print(json.load(open("'"$DIR"'/version.json"))["version"])' 2>/dev/null || echo '?')"
  _VPN="$(python3 -c 'import socket;s=socket.socket();s.settimeout(0.4);print("OPEN" if not s.connect_ex(("10.7.0.1",49152)) else "CLOSED")' 2>/dev/null || echo '?')"
  _PAIR="NO"; ([ -f "$DIR/pairing/rp_pairing_file.plist" ] || ls "$DIR/pairing"/*.remote.plist >/dev/null 2>&1) && _PAIR="OK"
  echo "✅ SideBot v${_VER} started in background (PID ${_PID})"
  if [ "$LOCAL_ONLY" = "1" ]; then
    echo "🌐 SideBot:  http://127.0.0.1:8080/sidebot.html"
    echo "🛍️ AppStore: http://127.0.0.1:8080/appstore.html"
    echo "📲 Icon SB:  http://127.0.0.1:8080/sidebot.mobileconfig"
    echo "📲 Icon AS:  http://127.0.0.1:8080/appstore.mobileconfig"
    echo "🔌 Tunnel:   10.7.0.1:49152 (${_VPN}) | Pairing: ${_PAIR}"
    echo "⚡ Quick:    sb  (or minis://)"
    echo "📜 Logs:     tail -f /tmp/bot.log"
  fi
  exit 0
fi
echo "🤖 Starting SideBot..."
set +e
while true; do
  python3 "$DIR/telegram_iloader_bot.py" $BOT_ARGS
  RC=$?
  [ "$RC" -eq 0 ] || [ "$RC" -eq 130 ] || [ "$RC" -eq 143 ] && exit "$RC"
  echo "⚠️ SideBot exited ($RC). Restarting in 2s..."
  sleep 2
done
