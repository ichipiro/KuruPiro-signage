#!/bin/bash
set -euo pipefail

# ==============================================================================
# warmup-reload.sh - 起動直後のキャッシュウォームアップ用リロード
# ==============================================================================
# ネットワークが不安定な環境で、起動直後に複数回リロードすることで
# 画像などのリソースをキャッシュに蓄積していきます。
#
# 指数バックオフ方式:
#   起動 → 1分後 → 3分後 → 7分後 → 15分後 → 終了
#   （合計4回のリロード、約15分で完了）
# ==============================================================================

export DISPLAY=:0

# リロード間隔（秒）: 60, 120, 240, 480 = 1分, 2分, 4分, 8分
# 累積: 1分後, 3分後, 7分後, 15分後
INTERVALS=(60 120 240 480)

echo "[kurupiro-warmup] キャッシュウォームアップ開始"
echo "[kurupiro-warmup] リロード予定: ${#INTERVALS[@]}回"

for i in "${!INTERVALS[@]}"; do
  interval=${INTERVALS[$i]}
  reload_num=$((i + 1))
  
  echo "[kurupiro-warmup] ${interval}秒後に ${reload_num}/${#INTERVALS[@]} 回目のリロードを実行..."
  sleep "$interval"
  
  # Chromium がまだ動いているか確認
  if ! pgrep -x chromium >/dev/null 2>&1; then
    echo "[kurupiro-warmup] Chromium が見つかりません。ウォームアップを中止します。"
    exit 0
  fi
  
  # F5キーでリロード
  if xdotool key F5 2>/dev/null; then
    echo "[kurupiro-warmup] リロード ${reload_num}/${#INTERVALS[@]} 完了 ($(date '+%H:%M:%S'))"
  else
    echo "[kurupiro-warmup] リロード失敗 (xdotool)"
  fi
done

echo "[kurupiro-warmup] キャッシュウォームアップ完了"
