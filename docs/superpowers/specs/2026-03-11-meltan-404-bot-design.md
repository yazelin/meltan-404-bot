# meltan-404-bot Design Spec

## Overview

A Telegram bot with architecture mirrored from `telegram-copilot-bot`, using GitHub Copilot CLI with `gpt-5-mini` model for all text/AI tasks and HuggingFace Inference API for image generation.

## Architecture

```
Telegram User → Cloudflare Worker (webhook + KV) → GitHub Actions → route_command.sh
                                                                      ├── Shell (direct)
                                                                      ├── Copilot CLI (gpt-5-mini)
                                                                      └── HuggingFace API (images)
```

Three-layer processing:

| Layer | Handles | Cost |
|-------|---------|------|
| Shell direct | `/download`, `/reset`, `/models` | Free |
| Copilot CLI (gpt-5-mini) | Chat, `/translate`, `/research` | 1 Premium Request each |
| HuggingFace API | `/draw` | ~$0.001/image |

## Commands

| Command | Handler | Description |
|---------|---------|-------------|
| (no prefix) | Copilot CLI gpt-5-mini | Conversational chat with history |
| `/draw [model:NAME] <prompt>` | HuggingFace API | Image generation, user-selectable model |
| `/translate <text>` | Copilot CLI gpt-5-mini | Chinese-English translation |
| `/download <url>` | yt-dlp | Video download, 50MB limit |
| `/research <topic>` | Copilot CLI gpt-5-mini + Tavily MCP | Web search + summary |
| `/reset` | Worker (instant) | Clear chat history |
| `/models` | Worker (instant) | List available image models |

## Image Generation Models

Users select via `/draw model:<shortname> <prompt>`. Default: `flux-schnell`.

| Shortname | Model ID | Provider | Notes |
|-----------|----------|----------|-------|
| `flux-dev` | black-forest-labs/FLUX.1-dev | fal-ai | Highest quality, slower |
| `flux-schnell` | black-forest-labs/FLUX.1-schnell | hf-inference | Fast, good quality (default) |
| `sdxl` | stabilityai/stable-diffusion-xl-base-1.0 | hf-inference | Classic, stable |
| `sd3` | stabilityai/stable-diffusion-3-medium | fal-ai | Balanced |

## File Structure

```
meltan-404-bot/
├── .github/
│   ├── workflows/
│   │   └── telegram-bot.yml
│   └── scripts/
│       ├── route_command.sh
│       ├── generate_image.py
│       ├── download_video.py
│       ├── send_telegram_message.py
│       ├── send_telegram_photo.py
│       └── send_telegram_video.py
├── worker/
│   ├── src/index.js
│   ├── wrangler.toml
│   └── package.json
├── dashboard/
│   ├── index.html
│   ├── style.css
│   └── app.js
├── prompt.md
├── setup.sh
└── .gitignore
```

## Cloudflare Worker

### Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/webhook` | POST | Telegram Secret | Receive Telegram updates |
| `/register?token=<secret>` | GET | TELEGRAM_SECRET | Register webhook |
| `/api/callback` | POST | X-Secret header | GitHub Actions callback |
| `/api/stats` | GET | None | Stats (totalMessages, totalDraws) |
| `/api/history/:chatId` | GET | None | Conversation history |
| `/api/reset/:chatId` | POST | X-Secret header | Clear chat memory |

### KV Structure

```
chat:<chatId>:user    → Array<{role, text, timestamp}>  (max 20)
chat:<chatId>:bot     → Array<{role, text, timestamp}>  (max 20)
stats                 → {totalMessages, totalDraws, totalResearches, totalTranslations}
```

## Secrets

### Cloudflare Worker (wrangler secret)

| Secret | Purpose |
|--------|---------|
| `TELEGRAM_BOT_TOKEN` | Telegram Bot API |
| `TELEGRAM_SECRET` | Webhook signature |
| `GITHUB_TOKEN` | Trigger workflows |
| `GITHUB_OWNER` | Repo owner |
| `GITHUB_REPO` | Repo name (meltan-404-bot) |
| `CALLBACK_TOKEN` | Protect callback endpoint |

### Worker Vars

| Var | Value |
|-----|-------|
| `ALLOWED_USERS` | `850654509` |

### GitHub Actions Secrets

| Secret | Purpose |
|--------|---------|
| `TELEGRAM_BOT_TOKEN` | Send messages |
| `CALLBACK_URL` | Worker callback endpoint |
| `CALLBACK_TOKEN` | Callback auth |
| `CHILD_COPILOT_TOKEN` | Copilot CLI auth |
| `HF_TOKEN` | HuggingFace image generation |
| `TAVILY_API_KEY` | Web search for /research |

## Copilot CLI Invocation

```bash
copilot --model gpt-5-mini --autopilot --yolo --max-autopilot-continues 10 -p "$PROMPT"
```

Lower `max-autopilot-continues` (10 vs 30) since we don't do code generation tasks.

## Dashboard

GitHub Pages frontend with:
- Stats cards (messages, draws, translations, researches)
- Chat bubble view (Telegram-style)
- Settings panel (Worker API URL, Chat ID)
- All data from Worker API endpoints

## Differences from telegram-copilot-bot

| Aspect | telegram-copilot-bot | meltan-404-bot |
|--------|---------------------|----------------|
| AI Model | Copilot default (Claude Sonnet) | Copilot `gpt-5-mini` |
| Chat pre-filter | Gemini Flash | None (all to Copilot) |
| Image gen | Gemini 3.0 Pro | HuggingFace (user-selectable) |
| App Factory | Yes (/app, /issue, /build, /msg) | No |
| Notify workflow | Yes | No |
| Templates | Yes (implement, review, skills) | No |
| Scripts | 15 | 6 |
| gemini_chat.py | Yes | No (removed) |
