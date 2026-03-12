#!/bin/bash
set -euo pipefail

# ==============================================================================
# app-switcher.sh - アプリケーション切り替えスクリプト
# ==============================================================================
# このスクリプトは、キャリアルーム用アプリケーションとChromiumキオスクモードを30秒ごとに切り替えるために使用されます。
# systemd timer から呼び出され、現在の状態に応じてアクティブを切り替えます。
# ==============================================================================

export DISPLAY=:0

# それぞれのウィンドウを取得する
APP_WINDOW=$(xdotool search --name "ebitv" 2>/dev/null || true)
CHROME_WINDOW=$(xdotool search --name "Chromium" 2>/dev/null || true)

ACTIVE_WINDOW=$(xdotool getactivewindow)
if [ -n "$APP_WINDOW" ] && [ "$ACTIVE_WINDOW" -eq "$APP_WINDOW" ]; then
  # アプリがアクティブならChromiumをアクティブにする
  if [ -n "$CHROME_WINDOW" ]; then
    xdotool windowactivate --sync "$CHROME_WINDOW"
    echo "[app-switcher] Chromium をアクティブに切り替えました"
  else
    echo "[app-switcher] 警告: Chromium のウィンドウが見つかりません" >&2
  fi
elif [ -n "$CHROME_WINDOW" ] && [ "$ACTIVE_WINDOW" -eq "$CHROME_WINDOW" ]; then
  # Chromiumがアクティブならアプリをアクティブにする
  if [ -n "$APP_WINDOW" ]; then
    xdotool windowactivate --sync "$APP_WINDOW"
    echo "[app-switcher] キャリアルーム用アプリケーションをアクティブに切り替えました"
  else
    echo "[app-switcher] 警告: キャリアルーム用アプリケーションのウィンドウが見つかりません" >&2
  fi
else
  echo "[app-switcher] 現在のアクティブウィンドウはキャリアルーム用アプリケーションでもChromiumでもありません。切り替えは行いません。"
fi
