# meltan-404-bot

Telegram 聊天機器人，基於 GitHub Copilot CLI (gpt-5-mini) 驅動，搭配 HuggingFace 圖片生成、yt-dlp 影片下載、Tavily 網路搜尋等功能。全部運行在 Serverless 架構上（Cloudflare Workers + GitHub Actions），無需自建伺服器。

## 架構

```
Telegram
  │
  ▼
Cloudflare Worker (Webhook 接收 + KV 儲存)
  │
  ▼
GitHub Actions (workflow_dispatch)
  │
  ▼
route_command.sh (指令路由)
  ├── Shell 直接處理 (/download)
  ├── Copilot CLI gpt-5-mini (聊天、/translate、/research、/draw)
  └── HuggingFace API (圖片生成)
  │
  ▼
Callback → Worker KV (儲存 Bot 回覆)
  │
  ▼
Dashboard (GitHub Pages) ← 讀取 /api/history & /api/stats
```

### 三層處理架構

| 層級 | 處理內容 | 成本 |
|------|---------|------|
| Worker 直接處理 | `/reset`、`/models` | 免費 |
| Shell 腳本 | `/download` (yt-dlp) | 免費 |
| Copilot CLI (gpt-5-mini) | 聊天、`/translate`、`/research`、`/draw` | ~1 Premium Request |
| HuggingFace API | 圖片生成 | ~$0.001/張 |

## 功能

| 指令 | 說明 | 處理方式 |
|------|------|---------|
| 直接輸入文字 | 一般聊天對話 | Copilot CLI gpt-5-mini |
| `/draw [model:NAME] 描述` | AI 圖片生成 | Copilot CLI + HuggingFace |
| `/translate 文字` | 中英互譯 | Copilot CLI gpt-5-mini |
| `/research 主題` | 深度研究報告 | Copilot CLI + Tavily MCP |
| `/download URL` | 影片下載 | yt-dlp (YouTube 會搜尋替代來源) |
| `/reset` | 清除對話記憶 | Worker 直接處理 |
| `/models` | 查看可用畫圖模型 | Worker 直接處理 |

### 圖片生成模型

透過 `/draw model:模型名 描述` 選擇模型，預設為 `flux-schnell`。

| 模型 | 說明 |
|------|------|
| `flux-schnell` | 快速、品質好（預設） |
| `flux-dev` | 最高品質、較慢 |
| `sdxl` | 經典穩定 |
| `sd3` | 平衡型 |

### YouTube 替代來源搜尋

YouTube 影片因 IP 限制無法在 GitHub Actions runner 上直接下載。Bot 會自動：
1. 偵測 YouTube URL（包含 youtube.com、youtu.be、yout-ube.com 等變體）
2. 透過 Tavily 搜尋影片標題
3. 在 Bilibili、Dailymotion、X/Twitter、Facebook、Vimeo 等平台尋找替代來源
4. 從替代平台下載並上傳至 GitHub Releases

## 專案結構

```
meltan-404-bot/
├── .github/
│   ├── workflows/
│   │   ├── telegram-bot.yml      # 主要 Bot 處理流程
│   │   └── deploy-dashboard.yml  # Dashboard 自動部署到 GitHub Pages
│   └── scripts/
│       ├── route_command.sh       # 指令路由（決定 Shell 或 Copilot CLI）
│       ├── generate_image.py      # HuggingFace 圖片生成
│       ├── download_video.py      # yt-dlp 影片下載
│       ├── send_telegram_message.py  # 傳送文字訊息 + Callback
│       ├── send_telegram_photo.py    # 傳送圖片 + Callback
│       └── send_telegram_video.py    # 傳送影片 + Callback
├── worker/
│   ├── src/index.js    # Cloudflare Worker（Webhook + API + KV）
│   ├── wrangler.toml   # Worker 設定
│   └── package.json
├── dashboard/
│   ├── index.html      # Dashboard 頁面
│   ├── app.js          # 前端邏輯
│   └── style.css       # 樣式
├── prompt.md           # Copilot CLI 的系統提示詞
├── setup.sh            # 一鍵設定腳本
├── update-cookies.sh   # YouTube Cookies 更新腳本
└── .gitignore
```

## 設定

### 前置需求

- [GitHub CLI](https://cli.github.com/) (`gh`)
- [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/) (`wrangler`)
- Node.js 20+
- Python 3
- 一個 [Telegram Bot Token](https://core.telegram.org/bots#botfather)

### 一鍵安裝

```bash
bash setup.sh
```

Setup 腳本會自動：
1. 檢查必要工具
2. 建立 Cloudflare KV 命名空間
3. 安裝 npm 依賴
4. 設定所有 Cloudflare Worker secrets
5. 部署 Worker
6. 註冊 Telegram Webhook
7. 設定 GitHub Actions secrets

### 需要的 Secrets

#### Cloudflare Worker Secrets（透過 `wrangler secret put`）

| Secret | 用途 |
|--------|------|
| `TELEGRAM_BOT_TOKEN` | Telegram Bot API Token |
| `TELEGRAM_SECRET` | Webhook 簽名驗證 |
| `GITHUB_TOKEN` | 觸發 GitHub Actions workflow |
| `GITHUB_OWNER` | GitHub 帳號名稱 |
| `GITHUB_REPO` | Repository 名稱 |
| `CALLBACK_TOKEN` | Callback 端點驗證 |

#### Worker 環境變數（在 `wrangler.toml` 設定）

| 變數 | 說明 |
|------|------|
| `ALLOWED_USERS` | 允許使用的 Telegram User ID（逗號分隔） |
| `ALLOWED_CHATS` | 允許使用的 Chat ID（逗號分隔） |

#### GitHub Actions Secrets（透過 `gh secret set`）

| Secret | 用途 |
|--------|------|
| `TELEGRAM_BOT_TOKEN` | 傳送 Telegram 訊息 |
| `CALLBACK_URL` | Worker callback 端點 URL |
| `CALLBACK_TOKEN` | Callback 驗證 Token |
| `CHILD_COPILOT_TOKEN` | Copilot CLI 認證 |
| `HF_TOKEN` | HuggingFace 圖片生成 API |
| `TAVILY_API_KEY` | Tavily 網路搜尋（/research 用） |
| `YT_COOKIES` | YouTube Cookies（選填，用於影片下載） |

## Cloudflare Worker API

| 端點 | 方法 | 驗證 | 說明 |
|------|------|------|------|
| `/webhook` | POST | Telegram Secret | 接收 Telegram 更新 |
| `/register?token=<secret>` | GET | TELEGRAM_SECRET | 註冊 Webhook |
| `/api/callback` | POST | X-Secret header | GitHub Actions 回報 Bot 回覆 |
| `/api/stats` | GET | 無 | 取得使用統計 |
| `/api/history/:chatId` | GET | 無 | 取得對話紀錄 |
| `/api/reset/:chatId` | POST | X-Secret header | 清除對話紀錄 |

### KV 資料結構

```
chat:<chatId>:user  → Array<{role, text, timestamp}>  (最多 20 筆)
chat:<chatId>:bot   → Array<{role, text, timestamp}>  (最多 20 筆)
stats               → {totalMessages, totalDraws, totalResearches, totalTranslations}
```

## Dashboard

部署在 GitHub Pages 上的前端介面，功能包含：

- 統計卡片（訊息數、畫圖數、翻譯數、研究數）
- Telegram 風格的對話氣泡檢視
- 設定面板（Worker API URL、Chat ID，存在 localStorage）

Dashboard 在推送 `dashboard/` 目錄變更到 main 時自動部署。

## 更新 YouTube Cookies

如果影片下載遇到 YouTube 驗證問題：

```bash
bash update-cookies.sh
```

會從本地瀏覽器匯出 cookies 並上傳到 GitHub Secrets。

## 技術細節

### Copilot CLI 呼叫方式

```bash
copilot --model gpt-5-mini --autopilot --yolo --max-autopilot-continues 10 -p "$PROMPT"
```

### Callback 機制

因為 Copilot CLI 不會將環境變數傳遞給子進程，Bot 的 callback 機制使用檔案 fallback：

1. Workflow 在啟動 Copilot CLI 前，將 callback 設定寫入 `/tmp/.callback_config`
2. 所有 send script 優先讀取環境變數，讀不到則 fallback 到 config 檔案
3. Callback 請求使用自訂 `User-Agent: meltan-404-bot/1.0` 以避免 Cloudflare Bot Fight Mode (Error 1010) 攔截

## License

MIT
