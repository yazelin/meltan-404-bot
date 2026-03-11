// --- KV Helpers ---

const MAX_HISTORY = 20;
const MAX_HISTORY_JSON_LENGTH = 2000;

async function appendHistory(kv, chatId, entry) {
  const suffix = entry.role === "bot" ? "bot" : "user";
  const key = `chat:${chatId}:${suffix}`;
  let history = [];
  try {
    const existing = await kv.get(key, "json");
    if (Array.isArray(existing)) history = existing;
  } catch {}
  const last = history[history.length - 1];
  if (last && last.role === entry.role && last.text === entry.text) {
    return history;
  }
  history.push(entry);
  if (history.length > MAX_HISTORY) {
    history = history.slice(-MAX_HISTORY);
  }
  await kv.put(key, JSON.stringify(history));
  return history;
}

async function getHistory(kv, chatId) {
  let user = [], bot = [];
  try {
    const u = await kv.get(`chat:${chatId}:user`, "json");
    if (Array.isArray(u)) user = u;
  } catch {}
  try {
    const b = await kv.get(`chat:${chatId}:bot`, "json");
    if (Array.isArray(b)) bot = b;
  } catch {}
  const merged = [...user, ...bot].sort((a, b) =>
    new Date(a.timestamp) - new Date(b.timestamp)
  );
  return merged.length > MAX_HISTORY * 2
    ? merged.slice(-MAX_HISTORY * 2)
    : merged;
}

function truncateHistoryForDispatch(history) {
  let entries = [...history];
  let json = JSON.stringify(entries);
  while (json.length > MAX_HISTORY_JSON_LENGTH && entries.length > 1) {
    entries = entries.slice(1);
    json = JSON.stringify(entries);
  }
  return json;
}

async function incrementStats(kv, field) {
  const stats = (await kv.get("stats", "json")) || {};
  stats[field] = (stats[field] || 0) + 1;
  await kv.put("stats", JSON.stringify(stats));
  return stats;
}

// --- Image model list ---

const IMAGE_MODELS = {
  "flux-schnell": { id: "black-forest-labs/FLUX.1-schnell", name: "FLUX.1 Schnell", desc: "Fast, good quality (default)" },
  "flux-dev":     { id: "black-forest-labs/FLUX.1-dev",     name: "FLUX.1 Dev",     desc: "Highest quality, slower" },
  "sdxl":         { id: "stabilityai/stable-diffusion-xl-base-1.0", name: "SDXL", desc: "Classic, stable" },
  "sd3":          { id: "stabilityai/stable-diffusion-3-medium",    name: "SD3 Medium", desc: "Balanced" },
};

// --- CORS & Response Helpers ---

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, X-Secret",
  };
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders() },
  });
}

// --- Main Router ---

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (url.pathname === "/webhook" && request.method === "POST") {
      return handleWebhook(request, env, ctx);
    }

    if (url.pathname === "/register") {
      const token = url.searchParams.get("token");
      if (token !== env.TELEGRAM_SECRET) {
        return new Response("Unauthorized", { status: 403 });
      }
      return registerWebhook(url, env);
    }

    if (url.pathname === "/api/callback" && request.method === "POST") {
      return handleCallback(request, env);
    }

    const historyMatch = url.pathname.match(/^\/api\/history\/(\d+)$/);
    if (historyMatch && request.method === "GET") {
      const history = await getHistory(env.BOT_MEMORY, historyMatch[1]);
      return jsonResponse(history);
    }

    if (url.pathname === "/api/stats" && request.method === "GET") {
      const stats = (await env.BOT_MEMORY.get("stats", "json")) || {};
      return jsonResponse(stats);
    }

    const resetMatch = url.pathname.match(/^\/api\/reset\/(\d+)$/);
    if (resetMatch && request.method === "POST") {
      const secret = request.headers.get("X-Secret");
      if (!env.CALLBACK_TOKEN || secret !== env.CALLBACK_TOKEN) {
        return new Response("Unauthorized", { status: 403 });
      }
      const chatId = resetMatch[1];
      await Promise.all([
        env.BOT_MEMORY.delete(`chat:${chatId}:user`),
        env.BOT_MEMORY.delete(`chat:${chatId}:bot`),
      ]);
      return jsonResponse({ ok: true, chatId });
    }

    return new Response("meltan-404-bot relay", { status: 200 });
  },
};

// --- Telegram Send Helper ---

async function sendTelegram(token, chatId, text) {
  await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, text }),
  });
}

// --- Webhook Handler ---

async function handleWebhook(request, env, ctx) {
  const secret = request.headers.get("X-Telegram-Bot-Api-Secret-Token");
  if (secret !== env.TELEGRAM_SECRET) {
    return new Response("Unauthorized", { status: 403 });
  }

  let update;
  try {
    update = await request.json();
  } catch {
    return new Response("Bad Request", { status: 400 });
  }

  if (!update.message?.text) {
    return new Response("OK", { status: 200 });
  }

  const msg = update.message;
  const userId = String(msg.from?.id || "");
  const chatId = String(msg.chat.id);
  const allowedUsers = (env.ALLOWED_USERS || "").split(",").map(s => s.trim()).filter(Boolean);
  const allowedChats = (env.ALLOWED_CHATS || "").split(",").map(s => s.trim()).filter(Boolean);

  if (!allowedUsers.includes(userId) && !allowedChats.includes(chatId)) {
    return new Response("OK", { status: 200 });
  }

  ctx.waitUntil((async () => {
    const text = msg.text.trim();

    // Handle /reset directly in Worker
    if (text === "/reset") {
      await Promise.all([
        env.BOT_MEMORY.delete(`chat:${chatId}:user`),
        env.BOT_MEMORY.delete(`chat:${chatId}:bot`),
      ]);
      await sendTelegram(env.TELEGRAM_BOT_TOKEN, chatId, "記憶已清除，我們可以重新開始了");
      return;
    }

    // Handle /models directly in Worker
    if (text === "/models") {
      const lines = Object.entries(IMAGE_MODELS).map(([key, m]) =>
        `• ${key} — ${m.name}: ${m.desc}`
      );
      const reply = `可用的畫圖模型：\n\n${lines.join("\n")}\n\n用法: /draw model:flux-dev 一隻太空貓`;
      await sendTelegram(env.TELEGRAM_BOT_TOKEN, chatId, reply);
      return;
    }

    // Store user message in KV
    await appendHistory(env.BOT_MEMORY, chatId, {
      role: "user",
      text: msg.text,
      timestamp: new Date().toISOString(),
    });

    // Increment stats
    await incrementStats(env.BOT_MEMORY, "totalMessages");
    const cmd = msg.text.split(" ")[0].toLowerCase();
    if (cmd === "/draw") await incrementStats(env.BOT_MEMORY, "totalDraws");
    if (cmd === "/research") await incrementStats(env.BOT_MEMORY, "totalResearches");
    if (cmd === "/translate") await incrementStats(env.BOT_MEMORY, "totalTranslations");

    // Read history then dispatch
    const history = await getHistory(env.BOT_MEMORY, chatId);
    await dispatchToGitHub(update, env, history);
  })());

  return new Response("OK", { status: 200 });
}

// --- Callback Handler ---

async function handleCallback(request, env) {
  const secret = request.headers.get("X-Secret");
  if (secret !== env.CALLBACK_TOKEN) {
    return jsonResponse({ error: "Unauthorized" }, 403);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Bad Request" }, 400);
  }

  const { type, chat_id, text, timestamp } = body;

  if (type === "bot_reply" && chat_id && text) {
    await appendHistory(env.BOT_MEMORY, chat_id, {
      role: "bot",
      text: text.slice(0, 500),
      timestamp: timestamp || new Date().toISOString(),
    });
  }

  return jsonResponse({ ok: true });
}

// --- GitHub Dispatch ---

async function dispatchToGitHub(update, env, history) {
  const msg = update.message;
  const historyJson = truncateHistoryForDispatch(history.slice(0, -1));

  const response = await fetch(
    `https://api.github.com/repos/${env.GITHUB_OWNER}/${env.GITHUB_REPO}/actions/workflows/telegram-bot.yml/dispatches`,
    {
      method: "POST",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "meltan-404-bot",
      },
      body: JSON.stringify({
        ref: "main",
        inputs: {
          chat_id: String(msg.chat.id),
          text: msg.text,
          username: msg.from?.username || "",
          history: historyJson,
        },
      }),
    }
  );

  if (!response.ok) {
    console.error("GitHub dispatch failed:", response.status, await response.text());
  }
}

// --- Webhook Registration ---

async function registerWebhook(requestUrl, env) {
  const webhookUrl = `${requestUrl.protocol}//${requestUrl.hostname}/webhook`;
  try {
    const result = await fetch(
      `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/setWebhook`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          url: webhookUrl,
          secret_token: env.TELEGRAM_SECRET,
          allowed_updates: ["message"],
          drop_pending_updates: true,
        }),
      }
    );
    const json = await result.json();
    return new Response(JSON.stringify(json, null, 2), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }
}
