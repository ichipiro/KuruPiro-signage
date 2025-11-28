#!/bin/bash
set -euo pipefail

# ==============================================================================
# setup.sh - 初回のみ実行するセットアップスクリプト
# ==============================================================================
# このスクリプトは Raspberry Pi の初回セットアップ時に1度だけ実行します。
# 毎回起動時の処理は start.sh が担当します。
# ==============================================================================

# ==== 設定値（必要に応じて修正） ====
PI_USER="ie"
APP_DIR="/opt/kurupiro"
INSTALL_FLAG="${APP_DIR}/.installed"

# ==== ここから下は基本的に編集不要 ====

if [ "${EUID}" -ne 0 ]; then
  echo "このスクリプトは sudo/root で実行してください" >&2
  exit 1
fi

echo "===== くるぴろ初期セットアップ開始 ====="

# すでにセットアップ済みなら何もしない
if [ -f "${INSTALL_FLAG}" ]; then
  echo "既にセットアップ済みのようです (${INSTALL_FLAG} が存在します)。"
  echo "やり直したい場合は、このファイルを削除してから再度実行してください。"
  exit 0
fi

# ユーザー存在チェック
if ! id "${PI_USER}" >/dev/null 2>&1; then
  echo "ユーザー ${PI_USER} が存在しません。PI_USER を修正してください。" >&2
  exit 1
fi

echo "[1/9] 必要パッケージのインストール"
apt-get update
apt-get install -y \
  git \
  nginx \
  chromium-browser \
  xdotool \
  curl

echo "[2/9] アプリディレクトリの確認"

if [ ! -d "${APP_DIR}/.git" ]; then
  echo "エラー: ${APP_DIR} にリポジトリが存在しません。" >&2
  echo "先に以下のコマンドで clone してください:" >&2
  echo "  sudo mkdir -p ${APP_DIR}" >&2
  echo "  sudo chown ${PI_USER}:${PI_USER} ${APP_DIR}" >&2
  echo "  git clone https://github.com/ichipiro/KuruPiro-signage.git ${APP_DIR}" >&2
  exit 1
fi

cd "${APP_DIR}"
chown -R "${PI_USER}:${PI_USER}" "${APP_DIR}"

echo "[3/11] .env の作成（なければ作成）"
if [ ! -f .env ]; then
  if [ -f .env.sample ]; then
    cp .env.sample .env
    chown "${PI_USER}:${PI_USER}" .env
    echo ".env を作成しました。必要に応じて後で編集してください。"
  else
    echo "エラー: .env.sample が存在しません。" >&2
    echo "リポジトリが正しく clone されているか確認してください。" >&2
    exit 1
  fi
fi

# .env 読み込み（nginx設定に使う）
# shellcheck disable=SC1091
source .env
UPSTREAM_URL="${KURUPIRO_UPSTREAM_URL:-https://example.com/kurupiro}"
KIOSK_URL="${KURUPIRO_KIOSK_URL:-http://localhost/}"
SHUTDOWN_TIME="${KURUPIRO_SHUTDOWN_TIME:-21:57}"
SHUTDOWN_HOUR="${SHUTDOWN_TIME%%:*}"
SHUTDOWN_MIN="${SHUTDOWN_TIME##*:}"

echo "[4/9] scripts ディレクトリとスクリプト作成"

mkdir -p scripts
chown -R "${PI_USER}:${PI_USER}" scripts

# 共通設定
cat > scripts/common.sh <<'EOF'
#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "${BASE_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${BASE_DIR}/.env"
  set +a
fi
EOF

# reload.sh（F5 リロード）
cat > scripts/reload.sh <<'EOF'
#!/bin/bash
set -euo pipefail

# ディスプレイ番号は環境に応じて調整（基本 :0 でOK）
DISPLAY=:0 xdotool key F5 || echo "[kurupiro] xdotool F5 失敗" >&2
EOF

chmod +x scripts/*.sh
chown "${PI_USER}:${PI_USER}" scripts/*.sh

echo "[5/9] nginx 設定"

NGINX_CONF="/etc/nginx/sites-available/kurupiro"

cat > "${NGINX_CONF}" <<EOF
server {
    listen 80 default_server;
    server_name _;

    root ${APP_DIR}/www;
    index offline.html;

    # 上流サイトへの proxy
    location / {
        proxy_pass ${UPSTREAM_URL};
        proxy_read_timeout 5s;
        proxy_connect_timeout 3s;
        error_page 500 502 503 504 /offline.html;
    }

    # オフライン画面
    location = /offline.html {
    }
}
EOF

mkdir -p "${APP_DIR}/www"
cp -r "${APP_DIR}/www/"* "${APP_DIR}/www/" 2>/dev/null || true
chown -R "${PI_USER}:${PI_USER}" "${APP_DIR}/www"

ln -sf "${NGINX_CONF}" /etc/nginx/sites-enabled/kurupiro
# デフォルトサイトは不要なら無効化
if [ -f /etc/nginx/sites-enabled/default ]; then
  rm -f /etc/nginx/sites-enabled/default
fi

systemctl restart nginx

echo "[6/9] systemd ユニット作成"

# kurupiro-start.service（起動時に start.sh を実行）
cat > /etc/systemd/system/kurupiro-start.service <<EOF
[Unit]
Description=kurupiro start (git pull + kiosk)
After=network-online.target nginx.service
Wants=network-online.target
Requires=nginx.service

[Service]
ExecStart=${APP_DIR}/scripts/start.sh
User=${PI_USER}
Group=${PI_USER}
Environment=DISPLAY=:0
Restart=always

[Install]
WantedBy=graphical.target
EOF

# reload 用 service + timer（2時間おき F5）
cat > /etc/systemd/system/kurupiro-reload.service <<EOF
[Unit]
Description=kurupiro browser soft reload (F5)

[Service]
Type=oneshot
ExecStart=${APP_DIR}/scripts/reload.sh
User=${PI_USER}
Group=${PI_USER}
EOF

cat > /etc/systemd/system/kurupiro-reload.timer <<'EOF'
[Unit]
Description=kurupiro browser soft reload timer

[Timer]
OnBootSec=30min
OnUnitActiveSec=2h
Unit=kurupiro-reload.service

[Install]
WantedBy=timers.target
EOF

echo "[7/9] 自動シャットダウン設定 (${SHUTDOWN_TIME})"

cat > /etc/cron.d/kurupiro-shutdown <<EOF
# 毎日 ${SHUTDOWN_TIME} にシャットダウン
${SHUTDOWN_MIN} ${SHUTDOWN_HOUR} * * * root /sbin/shutdown -h now
EOF

echo "[8/9] USB キーボード・マウス無効化 (usbhid blacklist)"

cat > /etc/modprobe.d/blacklist-usbhid.conf <<'EOF'
# くるぴろサイネージ用: USB HID デバイスを無効化
blacklist usbhid
EOF

echo "※ この設定を有効にするには再起動が必要です。"

echo "[9/9] systemd 有効化"

systemctl daemon-reload
systemctl enable kurupiro-start.service
systemctl enable kurupiro-reload.timer

touch "${INSTALL_FLAG}"
chown "${PI_USER}:${PI_USER}" "${INSTALL_FLAG}"

echo "===== セットアップ完了 ====="
echo "再起動後、自動起動し、${SHUTDOWN_TIME} にシャットダウンします。"
echo "USB HID 無効化の反映にも再起動が必要です。"
