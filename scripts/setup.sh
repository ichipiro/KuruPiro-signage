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
  xdotool \
  curl \
  unclutter \
  fonts-noto-cjk

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
RELOAD_INTERVAL="${KURUPIRO_RELOAD_INTERVAL:-2h}"

# X11セッション（rpd-x）に強制設定（Waylandではunclutterが動作しないため）
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
if [ -f "$LIGHTDM_CONF" ]; then
  sed -i 's/^user-session=.*/user-session=rpd-x/' "$LIGHTDM_CONF"
  sed -i 's/^autologin-session=.*/autologin-session=rpd-x/' "$LIGHTDM_CONF"
  echo "X11セッション(rpd-x)に設定しました。"
fi

# Waylandパネル(wf-panel-pi)を無効化（Wayland使用時のフォールバック）
LABWC_AUTOSTART="/etc/xdg/labwc/autostart"
if [ -f "$LABWC_AUTOSTART" ]; then
  sed -i 's|^/usr/bin/lwrespawn /usr/bin/wf-panel-pi|#/usr/bin/lwrespawn /usr/bin/wf-panel-pi|' "$LABWC_AUTOSTART" 2>/dev/null || true
fi

# unclutterの自動起動設定（システム全体のautostartに追加）
SYSTEM_AUTOSTART="/etc/xdg/lxsession/rpd-x/autostart"
if [ -f "$SYSTEM_AUTOSTART" ]; then
  if ! grep -q "^@unclutter" "$SYSTEM_AUTOSTART" 2>/dev/null; then
    echo "@unclutter -idle 0.1" >> "$SYSTEM_AUTOSTART"
    echo "rpd-xのautostartに@unclutterを追記しました。"
  fi
else
  # フォールバック: LXDE-pi用
  AUTOSTART_FILE="/home/${PI_USER}/.config/lxsession/LXDE-pi/autostart"
  mkdir -p "$(dirname "$AUTOSTART_FILE")"
  if ! grep -q "^@unclutter" "$AUTOSTART_FILE" 2>/dev/null; then
    echo "@unclutter -idle 0.1" >> "$AUTOSTART_FILE"
    chown "${PI_USER}:${PI_USER}" "$AUTOSTART_FILE"
    echo "LXDE-piのautostartに@unclutterを追記しました。"
  fi
fi

# デスクトップを黒背景にしてアイコン非表示（両方のセッション用）
for SESSION in rpd-x LXDE-pi; do
  DESKTOP_CONF="/home/${PI_USER}/.config/pcmanfm/${SESSION}/desktop-items-0.conf"
  mkdir -p "$(dirname "$DESKTOP_CONF")"
  cat > "$DESKTOP_CONF" <<EOF
[*]
desktop_bg=#000000
desktop_fg=#ffffff
desktop_shadow=#000000
wallpaper_mode=color
show_documents=0
show_trash=0
show_mounts=0
EOF
done
chown -R "${PI_USER}:${PI_USER}" "/home/${PI_USER}/.config/pcmanfm"
echo "デスクトップを黒背景に設定しました。"

# LXPanelを非表示（自動起動から削除）
for PANEL_AUTOSTART in "/etc/xdg/lxsession/rpd-x/autostart" "/etc/xdg/lxsession/LXDE-pi/autostart"; do
  if [ -f "$PANEL_AUTOSTART" ]; then
    sed -i 's/^@lxpanel/#@lxpanel/' "$PANEL_AUTOSTART" 2>/dev/null || true
    echo "$(basename $(dirname $PANEL_AUTOSTART))のLXPanelを無効化しました。"
  fi
done

echo "[4/9] scripts ディレクトリの権限設定"

chmod +x scripts/*.sh
chown -R "${PI_USER}:${PI_USER}" scripts

echo "[5/9] nginx 設定"

NGINX_CONF="/etc/nginx/sites-available/kurupiro"

# URLからホスト名とパスを抽出
UPSTREAM_HOST=$(echo "${UPSTREAM_URL}" | sed -E 's|https?://([^/]+).*|\1|')
UPSTREAM_BASE=$(echo "${UPSTREAM_URL}" | sed -E 's|(https?://[^/]+).*|\1|')
UPSTREAM_PATH=$(echo "${UPSTREAM_URL}" | sed -E 's|https?://[^/]+(.*)|\1|')

# パスの末尾にスラッシュを追加（なければ）
if [ -n "${UPSTREAM_PATH}" ] && [ "${UPSTREAM_PATH: -1}" != "/" ]; then
  UPSTREAM_PATH="${UPSTREAM_PATH}/"
fi

cat > "${NGINX_CONF}" <<EOF
server {
    listen 80 default_server;
    server_name _;

    root ${APP_DIR}/www;
    index offline.html;

    # DNS解決（オフライン時でも nginx が起動できるよう resolver を設定）
    resolver 8.8.8.8 1.1.1.1 valid=30s ipv6=off;
    resolver_timeout 5s;

    # 変数を使うことで、起動時の DNS 解決エラーを回避
    set \$upstream_host ${UPSTREAM_HOST};
    set \$upstream_base ${UPSTREAM_BASE};
    set \$upstream_path ${UPSTREAM_PATH};

    # アセットへのプロキシ（上流のルート直下）
    location /assets/ {
        proxy_pass \$upstream_base/assets/;
        proxy_read_timeout 5s;
        proxy_connect_timeout 3s;
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
        proxy_set_header Host \$upstream_host;

        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Allow-Methods "GET, OPTIONS" always;

        # DNS解決失敗時はオフラインページへ
        error_page 502 503 504 /offline.html;
    }

    # オフライン画面と関連ファイル（ローカルから配信）
    location = /offline.html {
        internal;
    }

    location ~ ^/offline\.(css|js)$ {
        # ローカルのwwwディレクトリから配信
    }

    location ~ ^/(logo|bus|ad-01|for-smartphone|qr)\.png$ {
        # ローカルのwwwディレクトリから配信（オフライン画面用アセット）
    }

    # 上流サイトへの proxy
    location / {
        proxy_pass \$upstream_base\$upstream_path;
        proxy_read_timeout 5s;
        proxy_connect_timeout 3s;
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
        proxy_set_header Host \$upstream_host;

        # CORSヘッダー（crossorigin属性のあるスクリプト/CSS用）
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Allow-Methods "GET, OPTIONS" always;

        error_page 500 502 503 504 /offline.html;
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

# nginx がオフラインでも起動できるよう、network-wait サービスを無効化
# これにより network-online.target がネットワーク接続を待たずに達成される
echo "[5.1/9] nginx のネットワーク依存を解除..."
systemctl disable --now NetworkManager-wait-online.service 2>/dev/null || true
systemctl mask NetworkManager-wait-online.service 2>/dev/null || true
systemctl disable --now systemd-networkd-wait-online.service 2>/dev/null || true
systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true

# nginx のオーバーライド設定（ネットワーク依存を最小化）
mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/override.conf <<EOF
[Unit]
# ネットワークがオフラインでも起動可能にする
After=
Wants=
Requires=
After=local-fs.target sysinit.target
EOF
systemctl daemon-reload

systemctl restart nginx

echo "[6/9] systemd ユニット作成"

# kurupiro-start.service（起動時に start.sh を実行）
cat > /etc/systemd/system/kurupiro-start.service <<EOF
[Unit]
Description=kurupiro start (git pull + kiosk)
After=graphical.target
Wants=nginx.service

[Service]
ExecStart=${APP_DIR}/scripts/start.sh
User=${PI_USER}
Group=${PI_USER}
Environment=DISPLAY=:0
Restart=on-failure
RestartSec=10

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

cat > /etc/systemd/system/kurupiro-reload.timer <<EOF
[Unit]
Description=kurupiro browser soft reload timer

[Timer]
OnBootSec=${RELOAD_INTERVAL}
OnUnitActiveSec=${RELOAD_INTERVAL}
Unit=kurupiro-reload.service

[Install]
WantedBy=timers.target
EOF

echo "[7/9] 自動シャットダウン設定 (${SHUTDOWN_TIME})"

cat > /etc/cron.d/kurupiro-shutdown <<EOF
# 毎日 ${SHUTDOWN_TIME} にシャットダウン
${SHUTDOWN_MIN} ${SHUTDOWN_HOUR} * * * root /sbin/shutdown -h now
EOF

echo "[8/11] USB キーボード・マウス無効化 (usbhid blacklist)"

cat > /etc/modprobe.d/blacklist-usbhid.conf <<'EOF'
# くるぴろサイネージ用: USB HID デバイスを無効化
blacklist usbhid
EOF

echo "※ この設定を有効にするには再起動が必要です。"

echo "[9/11] スクリーンセーバー・画面ブランク無効化"

# X11用: xset設定をautostartに追加
for SESSION in rpd-x LXDE-pi; do
  AUTOSTART_FILE="/etc/xdg/lxsession/${SESSION}/autostart"
  if [ -f "$AUTOSTART_FILE" ]; then
    # 既存のxset設定を削除
    sed -i '/^@xset/d' "$AUTOSTART_FILE" 2>/dev/null || true
    # スクリーンセーバー無効化とDPMS無効化を追加
    echo "@xset s off" >> "$AUTOSTART_FILE"
    echo "@xset s noblank" >> "$AUTOSTART_FILE"
    echo "@xset -dpms" >> "$AUTOSTART_FILE"
    echo "@xset dpms 0 0 0" >> "$AUTOSTART_FILE"
    echo "${SESSION}のスクリーンセーバー・DPMSを無効化しました。"
  fi
done

# lightdm.confにブランク無効化設定を追加
if [ -f "$LIGHTDM_CONF" ]; then
  if ! grep -q "^xserver-command=" "$LIGHTDM_CONF"; then
    sed -i '/^\[Seat:\*\]/a xserver-command=X -s 0 -dpms' "$LIGHTDM_CONF"
    echo "LightDMにスクリーンブランク無効化を設定しました。"
  fi
fi

# systemd のスリープ・サスペンド・ハイバネートを完全無効化
echo "systemdのスリープ機能を無効化しています..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
echo "systemdのスリープ機能を無効化しました。"

echo "[10/11] コンソールブランク無効化 (cmdline.txt)"

# Raspberry Pi OS の /boot/firmware/cmdline.txt または /boot/cmdline.txt
CMDLINE_FILE=""
if [ -f "/boot/firmware/cmdline.txt" ]; then
  CMDLINE_FILE="/boot/firmware/cmdline.txt"
elif [ -f "/boot/cmdline.txt" ]; then
  CMDLINE_FILE="/boot/cmdline.txt"
fi

if [ -n "$CMDLINE_FILE" ]; then
  # consoleblankとvt.global_cursor_defaultが未設定なら追加
  if ! grep -q "consoleblank=0" "$CMDLINE_FILE"; then
    sed -i 's/$/ consoleblank=0/' "$CMDLINE_FILE"
    echo "コンソールブランク無効化を追加しました。"
  fi
fi

echo "[11/12] systemd 有効化"

systemctl daemon-reload
systemctl enable kurupiro-start.service
systemctl enable kurupiro-reload.timer

echo "[12/12] バージョン情報埋め込み"

# Gitコミットハッシュをoffline.htmlに埋め込み
COMMIT_HASH=$(git -C "${APP_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
OFFLINE_HTML="${APP_DIR}/www/offline.html"
if [ -f "$OFFLINE_HTML" ]; then
  sed -i "s/<!--GIT_COMMIT_HASH-->/${COMMIT_HASH}/" "$OFFLINE_HTML"
  echo "コミットハッシュ ${COMMIT_HASH} を埋め込みました。"
fi

touch "${INSTALL_FLAG}"
chown "${PI_USER}:${PI_USER}" "${INSTALL_FLAG}"

echo "===== セットアップ完了 ====="
echo "再起動後、自動起動し、${SHUTDOWN_TIME} にシャットダウンします。"
echo "5秒後に自動的に再起動します..."
sleep 5
sudo reboot now
