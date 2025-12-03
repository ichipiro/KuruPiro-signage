#!/bin/bash
set -euo pipefail

# ==============================================================================
# start.sh - 毎回起動時に実行するスクリプト
# ==============================================================================
# このスクリプトは Raspberry Pi の起動時に毎回実行され、以下を行います:
#   1. git pull で最新のコードを取得
#   2. nginx の起動確認
#   3. Chromium キオスクモードの起動
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# .env 読み込み
if [ -f "${BASE_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${BASE_DIR}/.env"
  set +a
fi

# リポジトリURL
REPO_URL="https://github.com/ichipiro/KuruPiro-signage.git"

# 設定値（デフォルト）
KIOSK_URL="${KURUPIRO_KIOSK_URL:-http://localhost/}"

echo "===== くるぴろ起動スクリプト開始 ====="

# ------------------------------------------------------------------------------
# 1. git fetch & reset（最新コード取得、ローカル変更は破棄）
# ------------------------------------------------------------------------------
echo "[1/3] git fetch & reset 実行中..."
cd "${BASE_DIR}" || exit 1

# ネットワークエラーでも継続するため set +e
set +e

# リモートが未設定なら設定
if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "${REPO_URL}"
fi

# ローカル変更を破棄してリモートに強制同期
if git fetch origin && git reset --hard origin/main; then
  echo "[kurupiro] git fetch & reset 成功"
else
  echo "[kurupiro] git fetch に失敗しました。前回バージョンのまま続行します。" >&2
fi

# ------------------------------------------------------------------------------
# 2. nginx 起動確認（失敗してもChromium起動は続行）
# ------------------------------------------------------------------------------
echo "[2/3] nginx 起動確認..."

# ネットワーク/DNS準備を待つ（起動直後はDNS解決が失敗することがある）
MAX_NETWORK_WAIT=30
NETWORK_WAITED=0
while ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; do
  if [ $NETWORK_WAITED -ge $MAX_NETWORK_WAIT ]; then
    echo "[kurupiro] 警告: ネットワーク接続を確認できません（${MAX_NETWORK_WAIT}秒待機）" >&2
    break
  fi
  echo "[kurupiro] ネットワーク接続を待機中... (${NETWORK_WAITED}/${MAX_NETWORK_WAIT}秒)"
  sleep 1
  NETWORK_WAITED=$((NETWORK_WAITED + 1))
done

if systemctl is-active --quiet nginx; then
  echo "[kurupiro] nginx は既に起動しています"
else
  echo "[kurupiro] nginx を起動します..."
  # 最大3回リトライ（DNS解決待ち）
  NGINX_MAX_RETRY=3
  NGINX_RETRY=0
  NGINX_SUCCESS=false
  while [ $NGINX_RETRY -lt $NGINX_MAX_RETRY ]; do
    NGINX_RETRY=$((NGINX_RETRY + 1))
    echo "[kurupiro] nginx 起動試行 (${NGINX_RETRY}/${NGINX_MAX_RETRY})..."
    if sudo systemctl start nginx; then
      echo "[kurupiro] nginx 起動成功"
      NGINX_SUCCESS=true
      break
    else
      echo "[kurupiro] nginx 起動失敗、5秒後にリトライ..." >&2
      sleep 5
    fi
  done
  if [ "$NGINX_SUCCESS" = false ]; then
    echo "[kurupiro] 警告: nginx の起動に${NGINX_MAX_RETRY}回失敗しましたが、Chromium起動を続行します" >&2
  fi
fi

# ------------------------------------------------------------------------------
# 3. Chromium キオスク起動
# ------------------------------------------------------------------------------
echo "[3/3] Chromium キオスク起動..."

# X が立ち上がるまで少し待つ（必要に応じて調整）
sleep 5

# DISPLAY環境変数を設定（X11に接続するために必要）
export DISPLAY=:0
export XAUTHORITY=/home/ie/.Xauthority

# X11が利用可能になるまで待機
MAX_WAIT=30
WAITED=0
while ! xset q >/dev/null 2>&1; do
  if [ $WAITED -ge $MAX_WAIT ]; then
    echo "[kurupiro] エラー: X11サーバーに接続できません（${MAX_WAIT}秒待機）" >&2
    exit 1
  fi
  echo "[kurupiro] X11サーバーを待機中... (${WAITED}/${MAX_WAIT}秒)"
  sleep 1
  WAITED=$((WAITED + 1))
done
echo "[kurupiro] X11サーバーに接続しました"

# スクリーンセーバー・画面ブランク・DPMS無効化（常時表示）
xset s off 2>/dev/null || true
xset s noblank 2>/dev/null || true
xset s 0 0 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset dpms 0 0 0 2>/dev/null || true
echo "[kurupiro] スクリーンセーバー・DPMSを無効化しました"

# 背景を黒に設定
xsetroot -solid black 2>/dev/null || true

echo "[kurupiro] URL: ${KIOSK_URL}"

chromium \
  --kiosk "${KIOSK_URL}" \
  --incognito \
  --noerrdialogs \
  --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required \
  --disable-translate \
  --disable-features=Translate

echo "===== くるぴろ起動スクリプト終了 ====="
