// offline.js - オフラインページ用スクリプト

// 設定
const RETRY_INTERVAL = 60; // 秒
const KURUPIRO_SERVER_URL = 'https://kurupiro.ichipiro.net/';
const API_SERVER_URL = 'https://kurupiro.ichipiro.net/api/';

let retryCountdown = RETRY_INTERVAL;

// 現在時刻更新
function updateTime() {
  const now = new Date();
  const hours = String(now.getHours()).padStart(2, '0');
  const minutes = String(now.getMinutes()).padStart(2, '0');
  document.getElementById('current-time').textContent = hours + ':' + minutes;
}

// ステータス表示更新
function setStatus(elementId, status, message) {
  const el = document.getElementById(elementId);
  if (!el) return;

  let icon, className;
  switch (status) {
    case 'ok':
      icon = 'OK';
      className = 'status-ok';
      break;
    case 'error':
      icon = 'NG';
      className = 'status-error';
      break;
    case 'checking':
    default:
      icon = '...';
      className = 'status-checking';
      break;
  }

  const spinning = status === 'checking' ? 'spinning' : '';
  el.innerHTML = `
    <span class="status-icon ${spinning}">${icon}</span>
    <span class="${className}">${message}</span>
  `;
}

// ネットワーク状態チェック（実際の接続テストを行う）
async function checkNetwork() {
  setStatus('status-network', 'checking', '確認中...');
  
  // navigator.onLine は信頼性が低いため、実際にfetchで確認
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    
    // Google の generate_204 エンドポイントで接続確認
    await fetch('https://www.google.com/generate_204', {
      mode: 'no-cors',
      cache: 'no-store',
      signal: controller.signal
    });
    clearTimeout(timeout);
    
    setStatus('status-network', 'ok', '接続済み');
    return true;
  } catch (e) {
    setStatus('status-network', 'error', '未接続');
    return false;
  }
}

// DNS疎通チェック (画像読み込みで代替)
async function checkDNS(server, elementId) {
  setStatus(elementId, 'checking', '確認中...');
  
  try {
    // DNS直接チェックはブラウザでは不可能なので、
    // 各DNSプロバイダのサービスへのfetchで代替
    const url = server === '1.1.1.1' 
      ? 'https://cloudflare.com/favicon.ico'
      : 'https://www.google.com/favicon.ico';
    
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    
    const response = await fetch(url, { 
      mode: 'no-cors',
      cache: 'no-store',
      signal: controller.signal
    });
    clearTimeout(timeout);
    
    setStatus(elementId, 'ok', '到達可能');
    return true;
  } catch (e) {
    setStatus(elementId, 'error', '到達不可');
    return false;
  }
}

// くるぴろサーバーチェック
async function checkKurupiroServer() {
  setStatus('status-server', 'checking', '確認中...');
  
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);
    
    const response = await fetch(KURUPIRO_SERVER_URL, { 
      mode: 'no-cors',
      cache: 'no-store',
      signal: controller.signal
    });
    clearTimeout(timeout);
    
    setStatus('status-server', 'ok', '到達可能');
    return true;
  } catch (e) {
    setStatus('status-server', 'error', '到達不可');
    return false;
  }
}

// APIサーバーチェック
async function checkApiServer() {
  setStatus('status-api', 'checking', '確認中...');
  
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);
    
    const response = await fetch(API_SERVER_URL, { 
      mode: 'no-cors',
      cache: 'no-store',
      signal: controller.signal
    });
    clearTimeout(timeout);
    
    setStatus('status-api', 'ok', '到達可能');
    return true;
  } catch (e) {
    setStatus('status-api', 'error', '到達不可');
    return false;
  }
}

// 全チェック実行
async function runAllChecks() {
  // ネットワーク接続チェック
  const networkOk = await checkNetwork();
  
  // 並列でDNSチェック
  await Promise.all([
    checkDNS('1.1.1.1', 'status-dns-cloudflare'),
    checkDNS('8.8.8.8', 'status-dns-google')
  ]);
  
  // 並列でサーバーチェック
  const [serverOk, apiOk] = await Promise.all([
    checkKurupiroServer(),
    checkApiServer()
  ]);
  
  // 両サーバーに到達できたらリロードして本来のページへ
  if (serverOk && apiOk) {
    setTimeout(() => {
      // キャッシュをクリアしてハードリロード
      window.location.href = '/?nocache=' + Date.now();
    }, 2000);
  }
}

// リトライカウントダウン
function updateRetryCountdown() {
  retryCountdown--;
  
  if (retryCountdown <= 0) {
    retryCountdown = RETRY_INTERVAL;
    runAllChecks();
  }
  
  document.getElementById('retry-info').textContent = 
    `次の再チェックまで: ${retryCountdown}秒`;
  
  const progress = ((RETRY_INTERVAL - retryCountdown) / RETRY_INTERVAL) * 100;
  document.getElementById('progress-fill').style.width = progress + '%';
}

// ネットワーク状態変化のリスナー
window.addEventListener('online', () => {
  checkNetwork();
  runAllChecks();
});

window.addEventListener('offline', () => {
  checkNetwork();
});

// 初期化
document.addEventListener('DOMContentLoaded', () => {
  updateTime();
  setInterval(updateTime, 1000);
  
  runAllChecks();
  setInterval(updateRetryCountdown, 1000);
});
