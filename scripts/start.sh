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

# Gitコミットハッシュをoffline.htmlに埋め込み
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
OFFLINE_HTML="${BASE_DIR}/www/offline.html"
if [ -f "$OFFLINE_HTML" ]; then
  # 毎回プレースホルダーを更新（既に置換済みでも新しいハッシュに更新）
  sed -i "s/<!--GIT_COMMIT_HASH-->/${COMMIT_HASH}/g" "$OFFLINE_HTML"
  sed -i "s/[a-f0-9]\{7\}\(-dirty\)\?/${COMMIT_HASH}/g" "$OFFLINE_HTML" 2>/dev/null || true
  echo "[kurupiro] コミットハッシュ: ${COMMIT_HASH}"
fi

# ------------------------------------------------------------------------------
# 2. nginx 起動確認（失敗してもChromium起動は続行）
# ------------------------------------------------------------------------------
echo "[2/3] nginx 起動確認..."

# nginx起動を待つ（ネットワーク不要、ローカルサーバーなので）
NGINX_MAX_RETRY=10
NGINX_RETRY=0
NGINX_SUCCESS=false

while [ $NGINX_RETRY -lt $NGINX_MAX_RETRY ]; do
  NGINX_RETRY=$((NGINX_RETRY + 1))
  
  if systemctl is-active --quiet nginx; then
    echo "[kurupiro] nginx は起動しています"
    NGINX_SUCCESS=true
    break
  fi
  
  echo "[kurupiro] nginx 起動試行 (${NGINX_RETRY}/${NGINX_MAX_RETRY})..."
  sudo systemctl start nginx 2>/dev/null || true
  sleep 2
done

# nginxがまだ起動していなければ強制的に起動を試みる
if [ "$NGINX_SUCCESS" = false ]; then
  echo "[kurupiro] nginx が起動していません。再度起動を試みます..."
  sudo systemctl restart nginx || true
  sleep 3
  
  if systemctl is-active --quiet nginx; then
    echo "[kurupiro] nginx 起動成功"
    NGINX_SUCCESS=true
  else
    echo "[kurupiro] 警告: nginx の起動に失敗しました" >&2
    echo "[kurupiro] オフラインページを直接表示します" >&2
    # nginx なしの場合、ローカルHTMLファイルを直接表示
    KIOSK_URL="file://${BASE_DIR}/www/offline.html"
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
