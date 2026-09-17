// CC&VV のアイコン素材を生成するスクリプト（ビルドには不要。再生成したい時だけ実行）
//
//   ./make_icon.sh
//
// 生成物:
//   Resources/AppIcon.icns     アプリアイコン（カラー）
//   Resources/MenuBarIcon.pdf  メニューバー用テンプレートアイコン（黒+α）
//
// デザイン: 角丸四角の上半分「CC」/ 下半分「VV」、中央に仕切り線。
// カラー版は青系グラデーション、メニューバー版はテンプレート（黒）。

import Cocoa

// MARK: - 描画

/// b 内にアイコンを描画する。template = true のときメニューバー用（黒のみ）。
func drawArtwork(_ b: NSRect, template: Bool) {
    let s = min(b.width, b.height)
    let rect = NSRect(x: b.midX - s / 2, y: b.midY - s / 2, width: s, height: s)
    let inset = s * 0.045
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = body.width * 0.24
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    let lineColor: NSColor = template ? .black : .white
    let textColor: NSColor = template ? .black : .white

    if template {
        // メニューバー用: 黒の縁取り＋仕切り線＋ ⌘C / ⌘V（テンプレート画像）
        path.lineWidth = s * 0.055
        lineColor.setStroke()
        path.stroke()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let div = NSBezierPath()
        div.move(to: NSPoint(x: body.minX, y: body.midY))
        div.line(to: NSPoint(x: body.maxX, y: body.midY))
        div.lineWidth = s * 0.045
        lineColor.setStroke()
        div.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // ⌘ と文字の間を詰めて表示
        drawText("\u{2318}C", in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2),
                 fontSize: s * 0.30, color: textColor, tight: true)
        drawText("\u{2318}V", in: NSRect(x: body.minX, y: body.minY, width: body.width, height: body.height / 2),
                 fontSize: s * 0.30, color: textColor, tight: true)
    } else {
        // アプリアイコン: 青系グラデーション＋斜光のつや
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.38, green: 0.55, blue: 1.0, alpha: 1.0),
            NSColor(srgbRed: 0.18, green: 0.32, blue: 0.88, alpha: 1.0),
        ])
        gradient!.draw(in: path, angle: -90)

        // 上からのぞく淡いハイライト
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let gloss = NSBezierPath(roundedRect: body.insetBy(dx: body.width * 0.06, dy: body.height * 0.06)
                                .offsetBy(dx: 0, dy: body.height * 0.02),
                                xRadius: body.width * 0.20, yRadius: body.width * 0.20)
        NSGradient(colors: [
            NSColor(white: 1.0, alpha: 0.18),
            NSColor(white: 1.0, alpha: 0.0),
        ])?.draw(in: gloss, angle: -90)

        // 中央の仕切り線（両端を少し内側に）
        let div = NSBezierPath()
        div.move(to: NSPoint(x: body.minX + body.width * 0.06, y: body.midY))
        div.line(to: NSPoint(x: body.maxX - body.width * 0.06, y: body.midY))
        div.lineWidth = s * 0.022
        NSColor(white: 1.0, alpha: 0.55).setStroke()
        div.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // 文字（上半分 CC / 下半分 VV）
        drawText("CC", in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2),
                 fontSize: s * 0.27, color: textColor)
        drawText("VV", in: NSRect(x: body.minX, y: body.minY, width: body.width, height: body.height / 2),
                 fontSize: s * 0.27, color: textColor)
    }
}

func drawText(_ str: String, in rect: NSRect, fontSize: CGFloat, color: NSColor, tight: Bool = false) {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: para,
    ]
    if tight {
        // 文字間を詰める（メニューバーの極小サイズ用）
        attrs[.kern] = -fontSize * 0.12
    }
    let attr = NSAttributedString(string: str, attributes: attrs)
    let textSize = attr.size()
    let y = rect.midY - textSize.height / 2
    attr.draw(in: NSRect(x: rect.minX, y: y, width: rect.width, height: textSize.height))
}

// MARK: - 出力

func renderPNG(_ px: Int, template: Bool) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("rep") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawArtwork(NSRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)), template: template)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return data
}

func renderPDF(_ size: CGFloat, template: Bool) -> Data {
    let out = NSMutableData()
    guard
        let consumer = CGDataConsumer(data: out as CFMutableData),
        var box = Optional<CGRect>(CGRect(x: 0, y: 0, width: size, height: size)),
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)
    else { fatalError("pdf ctx") }

    ctx.beginPDFPage(nil)
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns
    drawArtwork(NSRect(x: 0, y: 0, width: size, height: size), template: template)
    NSGraphicsContext.restoreGraphicsState()
    ctx.endPDFPage()
    ctx.closePDF()
    return out as Data
}

// MARK: - main

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "Resources"
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// アプリアイコン（カラー）
let iconset = "\(outDir)/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in specs {
    try! renderPNG(px, template: false).write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
}

// メニューバー用テンプレートアイコン（PDF = どの解像度でもくっきり）
try! renderPDF(18, template: true).write(to: URL(fileURLWithPath: "\(outDir)/MenuBarIcon.pdf"))

print("🎨 アイコン生成完了: \(iconset) と \(outDir)/MenuBarIcon.pdf")
print("   （icns 化は make_icon.sh が行います）")
