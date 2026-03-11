/* ============================================================
   meltan-404-bot Dashboard — App Logic
   ============================================================ */

const CONFIG_KEY = 'meltan-404-dashboard-config';

const DEFAULTS = {
  apiUrl: '',
  chatId: '850654509',
};

function getConfig() {
  try {
    const raw = localStorage.getItem(CONFIG_KEY);
    if (raw) {
      const cfg = JSON.parse(raw);
      if (cfg.apiUrl && cfg.chatId) return cfg;
    }
  } catch {}
  return { ...DEFAULTS };
}

function saveConfig(config) {
  localStorage.setItem(CONFIG_KEY, JSON.stringify(config));
}

// Utils

function escapeHtml(str) {
  const d = document.createElement('div');
  d.textContent = String(str ?? '');
  return d.innerHTML;
}

function formatTime(dateString) {
  if (!dateString) return '';
  try {
    return new Date(dateString).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  } catch { return ''; }
}

// Toast

const TOAST_ICONS = {
  info:    'information-outline',
  success: 'check-circle-outline',
  error:   'alert-circle-outline',
};

function toast(message, type = 'info') {
  const container = document.getElementById('toast-container');
  const el = document.createElement('div');
  el.className = `toast toast--${type}`;
  el.innerHTML = `<i class="mdi mdi-${TOAST_ICONS[type] || 'information-outline'}" aria-hidden="true"></i><span>${escapeHtml(message)}</span>`;
  container.appendChild(el);
  setTimeout(() => {
    el.classList.add('removing');
    el.addEventListener('animationend', () => el.remove(), { once: true });
  }, 4000);
}

// Fetch

async function fetchStats(apiUrl) {
  const res = await fetch(`${apiUrl}/api/stats`);
  if (!res.ok) throw new Error(`Stats: ${res.status}`);
  return res.json();
}

async function fetchHistory(apiUrl, chatId) {
  const res = await fetch(`${apiUrl}/api/history/${chatId}`);
  if (!res.ok) throw new Error(`History: ${res.status}`);
  return res.json();
}

// Render Stats

function renderStats(stats) {
  ['totalMessages', 'totalDraws', 'totalTranslations', 'totalResearches'].forEach(key => {
    const el = document.querySelector(`.stat-num[data-key="${key}"]`);
    if (el) {
      el.textContent = (stats[key] ?? 0).toLocaleString();
      el.classList.remove('skeleton-text');
    }
  });
}

function renderStatsError() {
  document.querySelectorAll('.stat-num').forEach(el => {
    el.textContent = '—';
    el.classList.remove('skeleton-text');
  });
}

// Render Chat

function renderChat(history) {
  const container = document.getElementById('chat-messages');

  if (!history || !Array.isArray(history) || history.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <div class="empty-icon"><i class="mdi mdi-message-text-outline" aria-hidden="true"></i></div>
        <div class="empty-msg">No messages yet</div>
        <div class="empty-sub">Bot conversations will appear here</div>
      </div>`;
    return;
  }

  container.innerHTML = history.map(msg => {
    const isUser = msg.role === 'user';
    const text = msg.text || '';
    const isCommand = text.startsWith('/');
    const rowCls = isUser ? 'bubble-row--user' : 'bubble-row--bot';
    const bubbleCls = isUser ? 'bubble--user' : 'bubble--bot';
    const cmdCls = isCommand ? ' bubble--command' : '';
    const time = msg.timestamp || '';
    return `
      <div class="bubble-row ${rowCls}">
        <div>
          <div class="bubble ${bubbleCls}${cmdCls}">${escapeHtml(text)}</div>
          ${time ? `<div class="bubble-time">${formatTime(time)}</div>` : ''}
        </div>
      </div>`;
  }).join('');

  requestAnimationFrame(() => { container.scrollTop = container.scrollHeight; });
}

function renderChatError() {
  document.getElementById('chat-messages').innerHTML = `
    <div class="empty-state">
      <div class="empty-icon"><i class="mdi mdi-alert-outline" aria-hidden="true"></i></div>
      <div class="empty-msg">Could not load chat history</div>
      <div class="empty-sub">Check your Worker API URL and Chat ID</div>
    </div>`;
}

// Refresh

let isRefreshing = false;

async function refresh() {
  if (isRefreshing) return;
  const config = getConfig();
  if (!config.apiUrl) {
    toast('Please set Worker API URL in settings', 'error');
    renderStatsError();
    renderChatError();
    return;
  }
  isRefreshing = true;
  const refreshIcon = document.querySelector('.icon-refresh');
  if (refreshIcon) refreshIcon.classList.add('spinning');
  try {
    const [stats, history] = await Promise.all([
      fetchStats(config.apiUrl).catch(err => {
        console.error('Stats fetch failed:', err);
        toast('Worker offline — could not fetch stats', 'error');
        return null;
      }),
      fetchHistory(config.apiUrl, config.chatId).catch(err => {
        console.error('History fetch failed:', err);
        toast('Could not fetch chat history', 'error');
        return null;
      }),
    ]);
    if (stats)   renderStats(stats);   else renderStatsError();
    if (history) renderChat(history);   else renderChatError();
  } finally {
    isRefreshing = false;
    if (refreshIcon) refreshIcon.classList.remove('spinning');
  }
}

// Settings

function openSettings() {
  const config = getConfig();
  document.getElementById('input-api-url').value = config.apiUrl || '';
  document.getElementById('input-chat-id').value = config.chatId || '';
  document.getElementById('settings-panel').classList.add('open');
  document.getElementById('settings-panel').setAttribute('aria-hidden', 'false');
  document.getElementById('settings-overlay').classList.add('open');
  setTimeout(() => document.getElementById('input-api-url').focus(), 50);
}

function closeSettings() {
  document.getElementById('settings-panel').classList.remove('open');
  document.getElementById('settings-panel').setAttribute('aria-hidden', 'true');
  document.getElementById('settings-overlay').classList.remove('open');
  document.getElementById('btn-settings').focus();
}

function handleSaveSettings() {
  const apiUrl = document.getElementById('input-api-url').value.trim().replace(/\/+$/, '');
  const chatId = document.getElementById('input-chat-id').value.trim();
  if (!apiUrl || !chatId) {
    toast('Please fill in all fields', 'error');
    return;
  }
  if (!/^\d+$/.test(chatId)) {
    toast('Chat ID must be numeric', 'error');
    return;
  }
  saveConfig({ apiUrl, chatId });
  closeSettings();
  toast('Settings saved', 'success');
  refresh();
}

// Init

function init() {
  document.getElementById('btn-settings').addEventListener('click', () => {
    document.getElementById('settings-panel').classList.contains('open') ? closeSettings() : openSettings();
  });
  document.getElementById('btn-refresh').addEventListener('click', refresh);
  document.getElementById('btn-save-settings').addEventListener('click', handleSaveSettings);
  document.getElementById('btn-cancel-settings').addEventListener('click', closeSettings);
  document.getElementById('btn-close-settings').addEventListener('click', closeSettings);
  document.getElementById('settings-overlay').addEventListener('click', closeSettings);
  document.addEventListener('keydown', e => { if (e.key === 'Escape') closeSettings(); });

  const config = getConfig();
  if (!config.apiUrl) {
    openSettings();
  } else {
    refresh();
  }
}

document.addEventListener('DOMContentLoaded', init);
