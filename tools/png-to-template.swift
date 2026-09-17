// フルカラー画像（黒 plate + 白抜き文字）からメニューバー用テンプレート PNG を作る変換ツール
//
//   swiftc ... tools/png-to-template.swift -o /tmp/ccvv-p2t
//   /tmp/ccvv-p2t <元画像.png> <出力.png> <出力サイズpx>
//
// アルゴリズム:
//   1. 元画像を指定サイズへリサイズ
//   2. 画像外縁から白い領域を flood fill → 背景として透明に
//      （plate 外の白と、plate 内の白抜き文字を区別するため）
//   3. 残ったピクセルは「明るさ = 不透明度」に変換し、色は黒に
//      （黒 plate や枠線は明るさ≈0 なのでほぼ透明になる）

import Cocoa

let args = CommandLine.arguments
guard args.count >= 4,
      let src = NSImage(contentsOfFile: args[1]),
      let px = Int(args[3]) else {
    fatalError("usage: png-to-template <src.png> <out.png> <px>")
}

// ---- 1. リサイズして読み込み ----
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("rep") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
src.draw(in: NSRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)))
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.bitmapData else { fatalError("bitmapData") }
let bytesPerRow = rep.bytesPerRow
func lum(_ x: Int, _ y: Int) -> CGFloat {
    let i = y * bytesPerRow + x * 4
    return (CGFloat(data[i]) + CGFloat(data[i + 1]) + CGFloat(data[i + 2])) / 3.0 / 255.0
}
func alphaOf(_ x: Int, _ y: Int) -> CGFloat {
    CGFloat(data[y * bytesPerRow + x * 4 + 3]) / 255.0
}

// ---- 2. 外縁からの flood fill（白い背景 → 透明） ----
let threshold: CGFloat = 0.5
var visited = [Bool](repeating: false, count: px * px)
var queue: [(Int, Int)] = []

for x in 0..<px {
    for y in [0, px - 1] {
        if lum(x, y) >= threshold, alphaOf(x, y) > 0.5 { queue.append((x, y)); visited[y * px + x] = true }
    }
}
for y in 0..<px {
    for x in [0, px - 1] {
        if lum(x, y) >= threshold, alphaOf(x, y) > 0.5, !visited[y * px + x] {
            queue.append((x, y)); visited[y * px + x] = true
        }
    }
}

var head = 0
while head < queue.count {
    let (x, y) = queue[head]; head += 1
    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let nx = x + dx, ny = y + dy
        guard nx >= 0, nx < px, ny >= 0, ny < px else { continue }
        if !visited[ny * px + nx], lum(nx, ny) >= threshold, alphaOf(nx, ny) > 0.5 {
            visited[ny * px + nx] = true
            queue.append((nx, ny))
        }
    }
}

// ---- 3. 明るさ → 不透明度、色は黒 ----
for y in 0..<px {
    for x in 0..<px {
        let i = y * bytesPerRow + x * 4
        if visited[y * px + x] {
            data[i + 3] = 0 // 背景
        } else {
            let a = lum(x, y) * alphaOf(x, y)
            data[i] = 0; data[i + 1] = 0; data[i + 2] = 0
            data[i + 3] = UInt8(max(0, min(255, (a * 255.0).rounded())))
        }
    }
}

let out = URL(fileURLWithPath: args[2])

// ---- 4. 内容（不透明部分＝白抜き文字）の外接矩形にトリミング ----
// 黒 plate は明るさ≈0 で透明になるため、残った不透明ピクセルは文字だけ。
// その外接矩形を少しの余白付きで切り出し、メニューバーの狭い枠内で
// 文字を目いっぱい大きく見せる。
var bMinX = px, bMaxX = -1, bMinY = px, bMaxY = -1
for y in 0..<px {
    for x in 0..<px where data[y * bytesPerRow + x * 4 + 3] > 127 {
        bMinX = min(bMinX, x); bMaxX = max(bMaxX, x)
        bMinY = min(bMinY, y); bMaxY = max(bMaxY, y)
    }
}

if bMaxX >= bMinX {
    let w = bMaxX - bMinX + 1
    let h = bMaxY - bMinY + 1
    let pad = max(1, Int((Double(max(w, h)) * 0.03).rounded()))
    let x0 = max(0, bMinX - pad), y0 = max(0, bMinY - pad)
    let x1 = min(px - 1, bMaxX + pad), y1 = min(px - 1, bMaxY + pad)
    let cw = x1 - x0 + 1
    let ch = y1 - y0 + 1

    guard let crop = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: cw, pixelsHigh: ch,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let cd = crop.bitmapData else { fatalError("crop rep") }

    let cpr = crop.bytesPerRow
    for y in 0..<ch {
        for x in 0..<cw {
            let si = (y0 + y) * bytesPerRow + (x0 + x) * 4
            let di = y * cpr + x * 4
            cd[di] = data[si]; cd[di + 1] = data[si + 1]
            cd[di + 2] = data[si + 2]; cd[di + 3] = data[si + 3]
        }
    }
    guard let png = crop.representation(using: .png, properties: [:]) else { fatalError("crop png") }
    try! png.write(to: out)
    print("🖼 テンプレート化＋トリミング完了: \(out.lastPathComponent)（文字部分 \(cw)\u{00d7}\(ch) を切り出し）")
} else {
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try! png.write(to: out)
    print("🖼 テンプレート化完了: \(out.lastPathComponent)（内容が見つからずトリミングなし）")
}
