#!/usr/bin/env bash
# Route Telegram commands: handle simple ones in shell, forward others to Copilot CLI.
# Input env: CHAT_ID, TEXT, TELEGRAM_BOT_TOKEN, HF_TOKEN, HISTORY
# Output: sets GitHub Actions output needs_copilot=true/false
set -euo pipefail
set -f  # Disable globbing

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Helper functions ---

send_msg()      { python3 "$SCRIPTS_DIR/send_telegram_message.py" "$@"; }
send_photo()    { python3 "$SCRIPTS_DIR/send_telegram_photo.py" "$@"; }
send_video()    { python3 "$SCRIPTS_DIR/send_telegram_video.py" "$@"; }
generate_image(){ python3 "$SCRIPTS_DIR/generate_image.py" "$@"; }
download_video(){ python3 "$SCRIPTS_DIR/download_video.py" "$@"; }

set_output() {
  echo "needs_copilot=$1" >> "${GITHUB_OUTPUT:-/dev/null}"
}

send_error() {
  send_msg "$CHAT_ID" "❌ $1" || true
  post_callback "❌ $1"
}

# Post bot reply to callback for history storage
post_callback() {
  if [ -z "${CALLBACK_URL:-}" ] || [ -z "${CALLBACK_TOKEN:-}" ]; then
    return 0
  fi
  local payload
  payload=$(CB_TEXT="$1" python3 -c "
import json,os
from datetime import datetime,timezone
print(json.dumps({'type':'bot_reply','chat_id':os.environ.get('CHAT_ID',''),'text':os.environ['CB_TEXT'][:500],'timestamp':datetime.now(timezone.utc).isoformat()}))
")
  curl -s -X POST "$CALLBACK_URL" \
    -H "Content-Type: application/json" \
    -H "X-Secret: $CALLBACK_TOKEN" \
    -d "$payload" || true
}

# Extract a field from JSON on stdin
json_field() {
  python3 -c "import sys,json; print(json.load(sys.stdin).get('$1','${2:-}'))" 2>/dev/null
}

# Strip leading/trailing whitespace
TEXT="${TEXT#"${TEXT%%[![:space:]]*}"}"
TEXT="${TEXT%"${TEXT##*[![:space:]]}"}"

case "$TEXT" in
  /download\ *)
    URL="${TEXT#/download }"
    URL="${URL#"${URL%%[![:space:]]*}"}"

    RESULT=$(download_video "$URL") || true
    OK=$(printf '%s' "$RESULT" | json_field ok False || echo "False")

    if [ "$OK" != "True" ]; then
      ERROR=$(printf '%s' "$RESULT" | json_field error "下載失敗" || echo "下載失敗")
      send_error "下載失敗: $ERROR"
      set_output false
      exit 0
    fi

    FILE_PATH=$(printf '%s' "$RESULT" | json_field file_path "" || echo "")
    TITLE=$(printf '%s' "$RESULT" | json_field title "Video" || echo "Video")
    FILESIZE=$(printf '%s' "$RESULT" | json_field filesize 0 || echo "0")

    if ! [[ "$FILESIZE" =~ ^[0-9]+$ ]]; then
      FILESIZE=0
    fi

    if [ "$FILESIZE" -le 50000000 ]; then
      send_video "$CHAT_ID" "$FILE_PATH" "$TITLE" || send_error "影片傳送失敗"
      post_callback "[影片] $TITLE"
    else
      MSG="⚠️ 影片太大 ($(( FILESIZE / 1048576 ))MB)，超過 Telegram 50MB 限制"
      send_msg "$CHAT_ID" "$MSG"
      post_callback "$MSG"
    fi
    set_output false
    ;;

  /download)
    send_error "用法: /download <url>"
    set_output false
    ;;

  /draw\ *)
    # Route to Copilot CLI for prompt optimization + image generation
    set_output true
    ;;

  /draw)
    send_error "用法: /draw [model:模型名] <描述>
可用模型: flux-schnell (預設), flux-dev, sdxl, sd3
範例: /draw model:flux-dev 一隻太空貓"
    set_output false
    ;;

  /translate\ *|/research\ *)
    # These need Copilot CLI (gpt-5-mini)
    set_output true
    ;;

  /translate|/research)
    send_error "請在命令後加上內容"
    set_output false
    ;;

  /reset|/models)
    # Handled directly in Cloudflare Worker
    set_output false
    ;;

  *)
    # No command prefix: route to Copilot CLI for chat
    set_output true
    ;;
esac
