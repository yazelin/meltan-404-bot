#!/usr/bin/env python3
"""Send a photo to Telegram.
Usage: python send_telegram_photo.py <chat_id> <photo_path> [caption]
Env: TELEGRAM_BOT_TOKEN
"""
import json, os, sys, urllib.request
from datetime import datetime, timezone

def _load_callback_config():
    url = os.environ.get("CALLBACK_URL", "")
    token = os.environ.get("CALLBACK_TOKEN", "")
    if url and token:
        return url, token
    try:
        with open("/tmp/.callback_config") as f:
            cfg = json.load(f)
            return cfg.get("url", ""), cfg.get("token", "")
    except Exception:
        pass
    return "", ""

def post_callback(chat_id, text):
    callback_url, callback_token = _load_callback_config()
    if not callback_url or not callback_token:
        return
    payload = json.dumps({
        "type": "bot_reply",
        "chat_id": chat_id,
        "text": text[:500],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }).encode()
    req = urllib.request.Request(
        callback_url,
        data=payload,
        headers={"Content-Type": "application/json", "X-Secret": callback_token, "User-Agent": "meltan-404-bot/1.0"},
    )
    try:
        urllib.request.urlopen(req, timeout=5).read()
    except Exception as e:
        print(f"[post_callback] FAILED: {e}", file=sys.stderr)

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"ok": False, "error": "Usage: send_telegram_photo.py <chat_id> <photo_path> [caption]"}))
        sys.exit(1)
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat_id = sys.argv[1]
    photo_path = sys.argv[2]
    caption = sys.argv[3] if len(sys.argv) > 3 else ""
    # Telegram sendPhoto caption limit is 1024 characters
    if len(caption) > 1024:
        caption = caption[:1021] + "..."
    boundary = "----TelegramUpload"
    body = b""
    body += f"--{boundary}\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n{chat_id}\r\n".encode()
    if caption:
        body += f"--{boundary}\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\n{caption}\r\n".encode()
    with open(photo_path, "rb") as f:
        photo_data = f.read()
    body += f"--{boundary}\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"image.png\"\r\nContent-Type: image/png\r\n\r\n".encode()
    body += photo_data
    body += f"\r\n--{boundary}--\r\n".encode()
    url = f"https://api.telegram.org/bot{token}/sendPhoto"
    req = urllib.request.Request(url, data=body, headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    try:
        resp = urllib.request.urlopen(req)
        data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="replace")
        print(json.dumps({"ok": False, "error": f"Telegram API HTTP {e.code}: {error_body[:300]}"}))
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        sys.exit(1)
    post_callback(chat_id, f"[圖片] {caption}" if caption else "[圖片]")
    print(json.dumps({"ok": True, "message_id": data.get("result", {}).get("message_id")}))

if __name__ == "__main__":
    main()
