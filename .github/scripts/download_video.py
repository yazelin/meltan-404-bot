#!/usr/bin/env python3
"""Download a video using yt-dlp.
Usage: python download_video.py <url>
"""
import json, os, subprocess, sys

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "No URL provided"}))
        sys.exit(1)
    url = sys.argv[1]
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "yt-dlp"], stdout=subprocess.DEVNULL)
    output_dir = "/tmp/yt-dlp-output"
    os.makedirs(output_dir, exist_ok=True)
    output_template = os.path.join(output_dir, "%(id)s.%(ext)s")
    # Write cookies file if YT_COOKIES env is set
    cookies_file = None
    yt_cookies = os.environ.get("YT_COOKIES", "")
    if yt_cookies:
        cookies_file = os.path.join(output_dir, "cookies.txt")
        with open(cookies_file, "w") as f:
            f.write(yt_cookies)

    cmd = [sys.executable, "-m", "yt_dlp",
           "-f", "b",
           "-o", output_template,
           "--no-playlist", "--no-overwrites",
           "--restrict-filenames", "--print-json"]
    if cookies_file:
        cmd.extend(["--cookies", cookies_file])
    cmd.append(url)

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    except subprocess.TimeoutExpired:
        print(json.dumps({"ok": False, "error": "Download timed out (240s)"}))
        sys.exit(1)
    if result.returncode != 0:
        raw_err = result.stderr.strip()[-500:] if result.stderr else "Unknown error"
        # Detect YouTube sign-in requirement
        if "Sign in to confirm" in raw_err:
            if not yt_cookies:
                err_msg = "YouTube 需要登入驗證。請執行 bash update-cookies.sh 設定 cookies，或嘗試其他平台"
            else:
                err_msg = f"YouTube cookies 無法通過驗證（可能 IP 不同或已過期）。請重新執行 bash update-cookies.sh\n原始錯誤: {raw_err[-200:]}"
        else:
            err_msg = raw_err
        print(json.dumps({"ok": False, "error": err_msg}))
        sys.exit(1)
    try:
        lines = result.stdout.strip().split("\n")
        info = json.loads(lines[-1])
    except (json.JSONDecodeError, IndexError):
        print(json.dumps({"ok": False, "error": "Failed to parse yt-dlp output"}))
        sys.exit(1)
    filepath = info.get("_filename", "")
    if not filepath or not os.path.exists(filepath):
        vid = info.get("id")
        ext = info.get("ext")
        if vid and ext:
            filepath = os.path.join(output_dir, f"{vid}.{ext}")
        if not filepath or not os.path.exists(filepath):
            print(json.dumps({"ok": False, "error": "Downloaded file not found"}))
            sys.exit(1)
    print(json.dumps({"ok": True, "file_path": filepath, "title": info.get("title", "Unknown"), "filesize": os.path.getsize(filepath)}))

if __name__ == "__main__":
    main()
