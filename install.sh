#!/bin/sh
# CC&VV を /Applications にインストールし、ログイン時自動起動（LaunchAgent）を有効化する
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/CC&VV.app"
LABEL="dev.nico.ccvv"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI_DOMAIN="gui/$(id -u)"

# 0) 旧名 Copyman の残骸を掃除する（一度だけ）
OLD_LABEL="dev.nico.copyman"
launchctl bootout "$GUI_DOMAIN/$OLD_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
pkill -x Copyman 2>/dev/null || true
rm -rf "/Applications/Copyman.app"

# 1) 最新ビルド
"$ROOT/build.sh"

# 2) /Applications へ配置
pkill -x CCVV 2>/dev/null || true
sleep 1
rm -rf "$APP"
cp -R "$ROOT/build/CC&VV.app" /Applications/

# 3) LaunchAgent 登録（ログイン時に自動起動）
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/CCVV</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST_EOF

launchctl bootout "$GUI_DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$GUI_DOMAIN" "$PLIST"

echo "✅ インストール完了: $APP"
echo "   ログイン時自動起動: $PLIST"
echo "   解除は ./uninstall.sh"
echo ""
echo "⚠️  バンドルID変更（dev.nico.copyman → dev.nico.ccvv）のため、"
echo "    アクセシビリティ権限の再設定が一度だけ必要です:"
echo "    システム設定 > プライバシーとセキュリティ > アクセシビリティ で"
echo "    「CC&VV」をオン（古い Copyman が残れば − で削除）"
