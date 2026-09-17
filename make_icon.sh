#!/bin/sh
# アイコン素材（Resources/AppIcon.icns と Resources/MenuBarIcon.pdf）を
# 生成・更新するスクリプト。通常は一度実行すれば十分（成果物はリポジトリに同梱）。
#
# デザインを変えたいときは tools/make-icon.swift を編集して再実行してください。
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/Resources"
mkdir -p "$OUT"

if [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
    SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc
    SDK_FLAGS=(-sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
else
    SWIFTC=swiftc
    SDK_FLAGS=()
fi

# 生成スクリプトをその場で実行
"$SWIFTC" "${SDK_FLAGS[@]}" -O "$ROOT/tools/make-icon.swift" -o /tmp/ccvv-make-icon -framework Cocoa
/tmp/ccvv-make-icon "$OUT"

# iconset -> icns
iconutil -c icns "$OUT/AppIcon.iconset" -o "$OUT/AppIcon.icns"
rm -rf "$OUT/AppIcon.iconset"

echo "✅ アイコン更新完了: $OUT/AppIcon.icns / $OUT/MenuBarIcon.pdf"
