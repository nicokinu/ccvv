#!/bin/sh
# CC&VV のインストール（/Applications のアプリとログイン時自動起動）を解除する
# ※ ~/.ccvv_slots.json （スロットの内容）は消しません
set -eu

LABEL="dev.nico.ccvv"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI_DOMAIN="gui/$(id -u)"

launchctl bootout "$GUI_DOMAIN/$LABEL" 2>/dev/null || true
pkill -x CCVV 2>/dev/null || true
rm -f "$PLIST"
rm -rf "/Applications/CC&VV.app"

# 旧名 Copyman 時代の残骸も掃除する
OLD_LABEL="dev.nico.copyman"
launchctl bootout "$GUI_DOMAIN/$OLD_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
pkill -x Copyman 2>/dev/null || true
rm -rf "/Applications/Copyman.app"

echo "✅ アンインストール完了"
echo "   （スロットの内容を残す場合は ~/.ccvv_slots.json を手で削除してください）"
