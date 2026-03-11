#!/usr/bin/env bash
# meltan-404-bot setup wizard
set -euo pipefail

echo "=== meltan-404-bot Setup ==="
echo ""

# Check prerequisites
for cmd in gh wrangler node npm; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Required: $cmd not found. Please install it first."
    exit 1
  fi
done

echo "✅ All prerequisites found"
echo ""

# Get repo info
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
if [ -z "$REPO" ]; then
  echo "❌ Not in a GitHub repo. Please run 'gh repo create' first."
  exit 1
fi
OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"
echo "📦 Repository: $REPO"
echo ""

# Telegram Bot Token
read -rp "🤖 Telegram Bot Token: " TELEGRAM_BOT_TOKEN
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
  echo "❌ Token required"; exit 1
fi

# Generate secrets
TELEGRAM_SECRET=$(openssl rand -hex 16)
CALLBACK_TOKEN=$(openssl rand -hex 16)

# HuggingFace Token
read -rp "🎨 HuggingFace Token (HF_TOKEN): " HF_TOKEN

# Tavily API Key (optional)
read -rp "🔍 Tavily API Key (optional, for /research): " TAVILY_API_KEY

# Copilot Token
read -rp "🔑 Copilot GitHub Token (CHILD_COPILOT_TOKEN): " CHILD_COPILOT_TOKEN

echo ""
echo "=== Setting up Cloudflare Worker ==="

cd worker
npm install

# Create KV namespace
echo "Creating KV namespace..."
KV_OUTPUT=$(wrangler kv namespace create BOT_MEMORY 2>&1)
KV_ID=$(echo "$KV_OUTPUT" | grep -oP 'id = "\K[^"]+' || echo "")
if [ -n "$KV_ID" ]; then
  sed -i "s/PLACEHOLDER_KV_ID/$KV_ID/" wrangler.toml
  echo "✅ KV namespace created: $KV_ID"
else
  echo "⚠️  Could not auto-detect KV ID. Please update worker/wrangler.toml manually."
  echo "$KV_OUTPUT"
fi

# Set Worker secrets
echo "Setting Worker secrets..."
echo "$TELEGRAM_BOT_TOKEN" | wrangler secret put TELEGRAM_BOT_TOKEN
echo "$TELEGRAM_SECRET" | wrangler secret put TELEGRAM_SECRET
echo "$CALLBACK_TOKEN" | wrangler secret put CALLBACK_TOKEN
echo "$OWNER" | wrangler secret put GITHUB_OWNER
echo "$REPO_NAME" | wrangler secret put GITHUB_REPO

# Deploy Worker
echo "Deploying Worker..."
wrangler deploy
WORKER_URL=$(wrangler deployments list 2>&1 | grep -oP 'https://[^\s]+\.workers\.dev' | head -1 || echo "")

cd ..

echo ""
echo "=== Setting GitHub Actions Secrets ==="

gh secret set TELEGRAM_BOT_TOKEN --body "$TELEGRAM_BOT_TOKEN"
gh secret set CALLBACK_TOKEN --body "$CALLBACK_TOKEN"

if [ -n "$WORKER_URL" ]; then
  gh secret set CALLBACK_URL --body "${WORKER_URL}/api/callback"
  echo "✅ CALLBACK_URL: ${WORKER_URL}/api/callback"
fi

if [ -n "$HF_TOKEN" ]; then
  gh secret set HF_TOKEN --body "$HF_TOKEN"
fi

if [ -n "$TAVILY_API_KEY" ]; then
  gh secret set TAVILY_API_KEY --body "$TAVILY_API_KEY"
fi

if [ -n "$CHILD_COPILOT_TOKEN" ]; then
  gh secret set CHILD_COPILOT_TOKEN --body "$CHILD_COPILOT_TOKEN"
fi

# GitHub token for Worker to dispatch workflows
GH_DISPATCH_TOKEN=$(gh auth token)
echo "$GH_DISPATCH_TOKEN" | wrangler secret put GITHUB_TOKEN --cwd worker

echo ""
echo "=== Registering Webhook ==="

if [ -n "$WORKER_URL" ]; then
  curl -s "${WORKER_URL}/register?token=${TELEGRAM_SECRET}" | python3 -m json.tool
  echo ""
  echo "✅ Webhook registered"
fi

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Worker URL: ${WORKER_URL:-'(check Cloudflare dashboard)'}"
echo ""
echo "Next steps:"
echo "  1. Send a message to your bot on Telegram"
echo "  2. Deploy dashboard to GitHub Pages (Settings → Pages → Deploy from branch)"
echo ""
