#!/usr/bin/env bash
# meltan-404-bot setup wizard
set -euo pipefail

WORKER_NAME="meltan-404-relay"

echo "=== meltan-404-bot Setup ==="
echo ""

# Check prerequisites
MISSING=""
for cmd in gh wrangler node npm openssl curl python3; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING="$MISSING $cmd"
  fi
done
if [ -n "$MISSING" ]; then
  echo "❌ Missing required tools:$MISSING"
  exit 1
fi
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

# --- Collect all inputs first ---

read -rp "🤖 Telegram Bot Token: " TELEGRAM_BOT_TOKEN
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
  echo "❌ Telegram Bot Token is required"; exit 1
fi

echo ""
echo "GitHub PAT 需要以下權限："
echo "  - actions:write (觸發 workflow)"
echo "  - contents:read"
echo "  可以用 gh auth token 的值，或建立 Fine-grained PAT"
echo ""
read -rp "🔑 GitHub PAT (for dispatching workflows): " GITHUB_PAT
if [ -z "$GITHUB_PAT" ]; then
  echo "  ℹ️  未提供，將使用 gh auth token"
  GITHUB_PAT=$(gh auth token)
fi

read -rp "🎨 HuggingFace Token (HF_TOKEN, for /draw): " HF_TOKEN
read -rp "🔍 Tavily API Key (optional, for /research): " TAVILY_API_KEY
read -rp "🤖 Copilot GitHub Token (CHILD_COPILOT_TOKEN): " CHILD_COPILOT_TOKEN

# Auto-generate secrets
TELEGRAM_SECRET=$(openssl rand -hex 16)
CALLBACK_TOKEN=$(openssl rand -hex 16)

echo ""
echo "=== [1/5] Setting up KV Namespace ==="

# Check if KV already has the right ID in wrangler.toml
CURRENT_KV_ID=$(grep -oP 'id = "\K[^"]+' worker/wrangler.toml 2>/dev/null || echo "")

if [ "$CURRENT_KV_ID" = "PLACEHOLDER_KV_ID" ] || [ -z "$CURRENT_KV_ID" ]; then
  # Need to create or find KV namespace
  KV_TITLE="${WORKER_NAME}-BOT_MEMORY"
  KV_ID=""

  # Try to find existing namespace with this title
  EXISTING=$(wrangler kv namespace list 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for ns in data:
        if ns.get('title') == '$KV_TITLE':
            print(ns['id'])
            break
except: pass
" 2>/dev/null || echo "")

  if [ -n "$EXISTING" ]; then
    KV_ID="$EXISTING"
    echo "✅ Found existing KV namespace: $KV_ID"
  else
    # Create new
    KV_OUTPUT=$(wrangler kv namespace create BOT_MEMORY 2>&1 || true)
    KV_ID=$(echo "$KV_OUTPUT" | grep -oP 'id = "\K[^"]+' || echo "")
    if [ -n "$KV_ID" ]; then
      echo "✅ Created KV namespace: $KV_ID"
    else
      # Might already exist with default title, try to find it
      KV_ID=$(wrangler kv namespace list 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for ns in data:
        if 'meltan' in ns.get('title','').lower() or ns.get('title') == 'BOT_MEMORY':
            print(ns['id'])
            break
except: pass
" 2>/dev/null || echo "")
      if [ -n "$KV_ID" ]; then
        echo "✅ Found KV namespace: $KV_ID"
      else
        echo "❌ Could not create or find KV namespace."
        echo "   Please create manually: wrangler kv namespace create BOT_MEMORY"
        echo "   Then update worker/wrangler.toml with the KV ID"
        exit 1
      fi
    fi
  fi

  # Update wrangler.toml
  sed -i "s/PLACEHOLDER_KV_ID/$KV_ID/" worker/wrangler.toml 2>/dev/null || true
  # Also handle case where there's already a different ID
  sed -i "s|^id = \".*\"|id = \"$KV_ID\"|" worker/wrangler.toml
else
  echo "✅ KV namespace already configured: $CURRENT_KV_ID"
fi

echo ""
echo "=== [2/5] Installing Worker Dependencies ==="

cd worker
npm install --silent
cd ..

echo "✅ Dependencies installed"

echo ""
echo "=== [3/5] Setting Worker Secrets ==="

# Use printf to avoid newline issues, pipe to wrangler
printf '%s' "$TELEGRAM_BOT_TOKEN" | wrangler secret put TELEGRAM_BOT_TOKEN --cwd worker 2>&1 | tail -1
printf '%s' "$TELEGRAM_SECRET"     | wrangler secret put TELEGRAM_SECRET --cwd worker 2>&1 | tail -1
printf '%s' "$CALLBACK_TOKEN"      | wrangler secret put CALLBACK_TOKEN --cwd worker 2>&1 | tail -1
printf '%s' "$OWNER"               | wrangler secret put GITHUB_OWNER --cwd worker 2>&1 | tail -1
printf '%s' "$REPO_NAME"           | wrangler secret put GITHUB_REPO --cwd worker 2>&1 | tail -1
printf '%s' "$GITHUB_PAT"          | wrangler secret put GITHUB_TOKEN --cwd worker 2>&1 | tail -1

echo "✅ Worker secrets set"

echo ""
echo "=== [4/5] Deploying Worker ==="

wrangler deploy --cwd worker 2>&1 | tail -5

# Get Worker URL from wrangler.toml name
WORKER_URL="https://${WORKER_NAME}.yazelinj303.workers.dev"

# Verify Worker is responding
echo ""
echo "Verifying Worker..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$WORKER_URL" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ Worker is live at $WORKER_URL"
else
  echo "⚠️  Worker returned HTTP $HTTP_CODE (may need a moment to propagate)"
fi

echo ""
echo "=== [5/5] Setting GitHub Actions Secrets ==="

gh secret set TELEGRAM_BOT_TOKEN --body "$TELEGRAM_BOT_TOKEN"
gh secret set CALLBACK_URL --body "${WORKER_URL}/api/callback"
gh secret set CALLBACK_TOKEN --body "$CALLBACK_TOKEN"

[ -n "$HF_TOKEN" ]           && gh secret set HF_TOKEN --body "$HF_TOKEN"
[ -n "$TAVILY_API_KEY" ]     && gh secret set TAVILY_API_KEY --body "$TAVILY_API_KEY"
[ -n "$CHILD_COPILOT_TOKEN" ] && gh secret set CHILD_COPILOT_TOKEN --body "$CHILD_COPILOT_TOKEN"

echo "✅ GitHub Actions secrets set"

# Verify secrets
echo ""
echo "Configured secrets:"
gh secret list

echo ""
echo "=== Registering Telegram Webhook ==="

# Wait a moment for Worker to be fully ready
sleep 2

REGISTER_RESULT=$(curl -s "${WORKER_URL}/register?token=${TELEGRAM_SECRET}")
echo "$REGISTER_RESULT" | python3 -m json.tool 2>/dev/null || echo "$REGISTER_RESULT"

REG_OK=$(echo "$REGISTER_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ok', False))" 2>/dev/null || echo "False")
if [ "$REG_OK" = "True" ]; then
  echo "✅ Webhook registered successfully"
else
  echo "⚠️  Webhook registration may have failed. Check output above."
fi

echo ""
echo "========================================="
echo "  ✅ Setup Complete!"
echo "========================================="
echo ""
echo "  Worker URL:  $WORKER_URL"
echo "  Webhook:     ${WORKER_URL}/webhook"
echo "  Dashboard:   Deploy via GitHub Pages"
echo ""
echo "  Commands to test:"
echo "    - Send any message to your bot"
echo "    - /draw 一隻太空貓"
echo "    - /translate hello world"
echo "    - /models"
echo "    - /reset"
echo ""
