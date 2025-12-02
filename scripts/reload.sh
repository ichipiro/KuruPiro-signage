#!/bin/bash
set -euo pipefail

# ==============================================================================
# reload.sh - Chromium をリロード（F5キー送信）+ スクリーンセーバー無効化再適用
# ==============================================================================
# 2時間ごとに systemd timer から呼び出されます。
# ==============================================================================

export DISPLAY=:0

# スクリーンセーバー・DPMS無効化を再適用（念のため）
xset s off 2>/dev/null || true
xset s noblank 2>/dev/null || true
xset s 0 0 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset dpms 0 0 0 2>/dev/null || true

# Chromium をリロード
xdotool key F5 || echo "[kurupiro] xdotool F5 失敗" >&2
