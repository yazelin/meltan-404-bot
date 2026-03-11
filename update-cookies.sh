#!/usr/bin/env bash
# One-click YouTube cookies update for meltan-404-bot
# Usage: bash update-cookies.sh [browser]
# Supported browsers: chrome (default), firefox, edge, brave, opera, vivaldi
set -euo pipefail

BROWSER="${1:-chrome}"
COOKIES_FILE="/tmp/yt-cookies-$$.txt"
VENV_DIR="/tmp/ytdlp-venv-$$"

cleanup() { rm -f "$COOKIES_FILE"; rm -rf "$VENV_DIR"; }
trap cleanup EXIT

echo "=== 更新 YouTube Cookies ==="
echo "瀏覽器: $BROWSER"
echo ""

# Check gh
if ! command -v gh &>/dev/null; then
  echo "❌ 需要 gh CLI"; exit 1
fi
if ! command -v uv &>/dev/null; then
  echo "❌ 需要 uv"; exit 1
fi

# Setup venv + yt-dlp
echo "📦 安裝 yt-dlp..."
uv venv "$VENV_DIR" --quiet
source "$VENV_DIR/bin/activate"
uv pip install --quiet yt-dlp secretstorage

# Export cookies
echo "🍪 從 $BROWSER 匯出 cookies..."
yt-dlp --cookies-from-browser "$BROWSER" --cookies "$COOKIES_FILE" "https://www.youtube.com" 2>&1 | head -3

COOKIE_COUNT=$(grep -c "^[^#]" "$COOKIES_FILE" 2>/dev/null || echo "0")
if [ "$COOKIE_COUNT" -lt 5 ]; then
  echo "❌ 只匯出 $COOKIE_COUNT 個 cookies，可能有問題。請確認 $BROWSER 已登入 YouTube"
  exit 1
fi
echo "✅ 匯出 $COOKIE_COUNT 個 cookies"

# Upload to GitHub
echo "📤 上傳到 GitHub Secret..."
gh secret set YT_COOKIES < "$COOKIES_FILE"

deactivate
echo ""
echo "✅ 完成！YT_COOKIES 已更新"
