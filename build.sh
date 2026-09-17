#!/bin/sh
# CC&VV.app をビルドするスクリプト（Xcode プロジェクトは不要）
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CC&VV"
EXE_NAME="CCVV"
APP="$ROOT/build/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Xcode のライセンス未同意時でも動くよう、Command Line Tools の swiftc を優先して使う
if [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
    SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
    SDK_FLAGS=(-sdk "$SDK")
else
    SWIFTC=swiftc
    SDK_FLAGS=()
fi

"$SWIFTC" "${SDK_FLAGS[@]}" -O "$ROOT/Sources/main.swift" \
    -o "$APP/Contents/MacOS/$EXE_NAME" \
    -framework Cocoa

# アイコン素材
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp "$ROOT/Resources/MenuBarIcon.pdf" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CCVV</string>
    <key>CFBundleIdentifier</key>
    <string>dev.nico.ccvv</string>
    <key>CFBundleName</key>
    <string>CC&amp;VV</string>
    <key>CFBundleDisplayName</key>
    <string>CC&amp;VV</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# 安定した自己署名証明書があればそれを使い、無ければ ad-hoc 署名にフォールバック
# （自己署名証明書で署名しておくと、再ビルドしてもアクセシビリティ権限が外れない）
# ※ 証明書の名称は旧名 "Copyman Code Signing" のまま（./certs.sh で作成）
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Copyman Code Signing" | head -1 | awk '{print $2}' || true)
if [ -n "$IDENTITY" ]; then
    echo "🔏 自己署名証明書で署名します: $IDENTITY"
    codesign --force --sign "$IDENTITY" --timestamp=none "$APP" 2>/dev/null \
        || codesign --force --sign "$IDENTITY" "$APP"
else
    echo "ℹ️  証明書が見つからないため ad-hoc 署名します（再ビルド毎に権限の再許可が必要）"
    echo "    一度だけ ./certs.sh を実行すると解消します"
    codesign --force --sign - "$APP" 2>/dev/null || true
fi

echo "✅ ビルド完了: $APP"
echo "   起動: open \"$APP\""
