#!/bin/sh
# アイコン素材（Resources/AppIcon.icns と Resources/MenuBarIcon.pdf）を
# 生成・更新するスクリプト。通常は一度実行すれば十分（成果物はリポジトリに同梱）。
#
# アプリアイコン:
#   Resources/icon-src.png（1024px 相当の元画像）があればそれから icns 化。
#   元画像が無い場合のみ tools/make-icon.swift のベクター描画にフォールバック。
# メニューバーアイコン:
#   tools/make-icon.swift で生成した白黒テンプレート PDF（常時ベクター）。
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/Resources"
SRC="$OUT/icon-src.png"
mkdir -p "$OUT"

iconset="$OUT/AppIcon.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"

if [ -f "$SRC" ]; then
    # 元画像（1024px 前提。それ以外なら 1024 にリサンプル）から iconset を展開
    echo "🖼  元画像から生成します: $SRC"
    for spec in "16:icon_16x16.png" "32:icon_16x16@2x.png" \
                "32:icon_32x32.png" "64:icon_32x32@2x.png" \
                "128:icon_128x128.png" "256:icon_128x128@2x.png" \
                "256:icon_256x256.png" "512:icon_256x256@2x.png" \
                "512:icon_512x512.png" "1024:icon_512x512@2x.png"; do
        px="${spec%%:*}"
        name="${spec#*:}"
        sips -s format png -Z "$px" "$SRC" --out "$iconset/$name" >/dev/null
    done
else
    echo "ℹ️  icon-src.png が無いのでベクター描画で生成します"
fi

# ベクター描画ツール（メニューバー用 PDF と、icon-src が無い場合のアプリアイコン）
if [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
    SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc
    SDK_FLAGS=(-sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
else
    SWIFTC=swiftc
    SDK_FLAGS=()
fi
"$SWIFTC" "${SDK_FLAGS[@]}" -O "$ROOT/tools/make-icon.swift" -o /tmp/ccvv-make-icon -framework Cocoa

if [ -f "$SRC" ]; then
    # メニューバー用 PDF だけ生成（アプリアイコンは元画像を使うので iconset は書かせない）
    mkdir -p /tmp/ccvv-icon-vec
    /tmp/ccvv-make-icon /tmp/ccvv-icon-vec >/dev/null
    cp /tmp/ccvv-icon-vec/MenuBarIcon.pdf "$OUT/MenuBarIcon.pdf"
    rm -rf /tmp/ccvv-icon-vec
else
    /tmp/ccvv-make-icon "$OUT"
    iconset="$OUT/AppIcon.iconset"
fi

# メニューバーアイコン: 元画像（menubar-src.png）があればテンプレート化して優先使用。
# 黒 plate + 白抜き文字 → 白抜き文字だけを不透明にした白黒テンプレート PNG を生成する。
if [ -f "$OUT/menubar-src.png" ]; then
    echo "🖼  メニューバーアイコンを元画像からテンプレート化します: $OUT/menubar-src.png"
    "$SWIFTC" "${SDK_FLAGS[@]}" -O "$ROOT/tools/png-to-template.swift" -o /tmp/ccvv-p2t -framework Cocoa
    /tmp/ccvv-p2t "$OUT/menubar-src.png" "$OUT/MenuBarIcon.png" 384
    rm -f /tmp/ccvv-p2t
fi

# iconset -> icns
iconutil -c icns "$iconset" -o "$OUT/AppIcon.icns"
rm -rf "$iconset"
rm -f /tmp/ccvv-make-icon

echo "✅ アイコン更新完了: $OUT/AppIcon.icns / $OUT/MenuBarIcon.pdf"
