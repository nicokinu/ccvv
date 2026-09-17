// CC&VV - 連続押しでスロットにコピー / スロットからペースト
//
//   Cmd+C x1 : 通常コピー（スロット1 = システムのクリップボード）
//   Cmd+C x2 : クリップボードの内容をスロット2に保存
//   Cmd+C x3 : スロット3に保存
//   Cmd+V x1 : 通常ペースト
//   Cmd+V x2 : スロット2をペースト
//   Cmd+V x3 : スロット3をペースト
//
// メニューバー（CC/VV アイコン）に常駐するアクセサリアプリ。

import Cocoa
import Carbon.HIToolbox

// MARK: - 設定

let kMaxSlot = 4                              // 対応する最大スロット番号
let kPressWindow: TimeInterval = 0.35         // 連続押しとみなす最大間隔（秒）
let kCaptureDelay: TimeInterval = 0.15        // Cmd+C後にクリップボードを読むまでの待ち（秒）
let kRestoreDelay: TimeInterval = 0.25        // スロットペースト後に元へ戻すまでの待ち（秒）
let kSelfTag: Int64 = 0x63_70_79              // 自分が打ち込んだイベントの目印

let kSlotFile = ("~/.ccvv_slots.json" as NSString).expandingTildeInPath
/// 旧名（Copyman）時代のスロットファイル。新ファイルが無い時に引っ越す
let kLegacySlotFile = ("~/.copyman_slots.json" as NSString).expandingTildeInPath
let kLogFile = ("~/.ccvv.log" as NSString).expandingTildeInPath

/// デバッグログのスイッチ。配布用は false（~/.ccvv.log にコピペ内容が
/// 残らないようにするため）。切り分けしたいときだけ true にして再ビルドする。
let kDebugLog = false

/// デバッグ用ログ（kDebugLog が true のときのみ ~/.ccvv.log に追記）
func blog(_ msg: String) {
    guard kDebugLog else { return }
    let df = DateFormatter()
    df.dateFormat = "HH:mm:ss.SSS"
    let line = "[\(df.string(from: Date()))] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let fh = FileHandle(forWritingAtPath: kLogFile) {
        defer { try? fh.close() }
        fh.seekToEndOfFile()
        fh.write(data)
    } else {
        try? data.write(to: URL(fileURLWithPath: kLogFile))
    }
}

// 打ち込んだイベントに目印を付けるためのフィールド
let kUserDataField = CGEventField.eventSourceUserData

// MARK: - クリップボード

func readClipboard() -> String? {
    NSPasteboard.general.string(forType: .string)
}

func writeClipboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}

/// クリップボード全体（全項目・全タイプ）のデータコピー
/// テキストだけでなく画像などの項目もそのまま復元するために使う
typealias ClipboardSnapshot = [[NSPasteboard.PasteboardType: Data]]

func snapshotClipboard() -> ClipboardSnapshot {
    (NSPasteboard.general.pasteboardItems ?? []).map { item in
        var dict: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types {
            if let data = item.data(forType: type) {
                dict[type] = data
            }
        }
        return dict
    }
}

func restoreClipboard(_ snapshot: ClipboardSnapshot) {
    let pb = NSPasteboard.general
    pb.clearContents()
    guard !snapshot.isEmpty else { return }
    let items = snapshot.map { dict -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in dict {
            item.setData(data, forType: type)
        }
        return item
    }
    pb.writeObjects(items)
}

func now() -> TimeInterval {
    ProcessInfo.processInfo.systemUptime
}

// MARK: - イベントタップ本体

final class CopymanController {
    static let shared = CopymanController()

    private var slots: [String: String] = [:]
    private(set) var tap: CFMachPort?

    private var cCount = 0
    private var lastC: TimeInterval = 0
    private var vCount = 0
    private var lastV: TimeInterval = 0
    private var copyBurstItem: DispatchWorkItem?
    private var pasteBurstItem: DispatchWorkItem?
    private var restoreItem: DispatchWorkItem?
    private var swallowVRelease = false

    private init() {
        load()
    }

    // ---- スロットの永続化 ----

    private func load() {
        let fm = FileManager.default
        // 旧名 Copyman からの移行：まだ新ファイルが無ければ引き継ぐ
        if !fm.fileExists(atPath: kSlotFile), fm.fileExists(atPath: kLegacySlotFile) {
            try? fm.moveItem(atPath: kLegacySlotFile, toPath: kSlotFile)
        }
        guard let data = fm.contents(atPath: kSlotFile),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        slots = dict
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(slots) else { return }
        let url = URL(fileURLWithPath: kSlotFile)
        try? data.write(to: url, options: .atomic)
        // スロットは平文（パスワード等）なので他ユーザーから読ませない
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: kSlotFile)
    }

    func slotText(_ slot: Int) -> String? {
        slots[String(slot)]
    }

    private func setSlot(_ slot: Int, _ text: String) {
        slots[String(slot)] = text
        save()
    }

    /// 全スロットとクリップボードを消去する（パスワード等の残存防止）
    func clearAll() {
        // 保留中の「スロット1へ戻す」タイマーが古い秘密を再投入してしまうので止める
        restoreItem?.cancel()
        restoreItem = nil
        slots.removeAll()
        save()
        NSPasteboard.general.clearContents()
        blog("全スロットとクリップボードを消去した")
    }

    // ---- タップの開始 ----

    /// 権限の付与・失敗を通知するコールバック（メインスレッドで呼ばれる）
    var onTrustedChange: ((Bool) -> Void)?

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func startTap(prompt: Bool = true) -> Bool {
        if tap != nil {
            onTrustedChange?(true)
            return true
        }
        // 権限が無い状態で tapCreate すると、イベントが永久に届かない
        // 死んだタップが返ることがある。先に許可済みかを確認する。
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        guard trusted else {
            onTrustedChange?(false)
            return false
        }

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        )
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            onTrustedChange?(false)
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        onTrustedChange?(true)
        return true
    }

    /// 起動後に権限が付与されたことを検して、タップを自動的に開始する
    func startTrustPolling() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, self.tap == nil, self.isTrusted else { return }
            if self.startTap(prompt: false) {
                NSLog("CC&VV: アクセシビリティ権限が付与されたのでタップを開始しました")
            }
        }
    }

    // ---- タップからのコールバック（メインスレッドで呼ばれる） ----

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 自分が打ち込んだイベントは何もせず通す
        if event.getIntegerValueField(kUserDataField) == kSelfTag {
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        // Cmd 単体（Shift などは除外）で押された C / V のみ対象
        let cmdOnly = event.flags.contains(.maskCommand)
            && event.flags.intersection([.maskShift, .maskControl, .maskAlternate]).isEmpty
        guard cmdOnly else { return Unmanaged.passUnretained(event) }

        // キーリピート（長押し）は無視
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if keyCode == CGKeyCode(kVK_ANSI_C) {
            // keyDown のみカウント（keyUp も数えると1回のコピーが連続押しになる）
            if type == .keyDown {
                copyPressed()
            }
            return Unmanaged.passUnretained(event)  // アプリ本来のコピーには触らない
        }

        if keyCode == CGKeyCode(kVK_ANSI_V) {
            if type == .keyDown {
                return pastePressed()              // 連続押しなので一旦止める
            } else {
                // 抑止した keyDown に対応する keyUp も止める
                if swallowVRelease { return nil }
                return Unmanaged.passUnretained(event)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // ---- コピー ----
    //
    // 押し終わる（連続押しの間隔があく）まで待ってから、押した回数で判定する:
    //   1回 -> 通常コピー（クリップボード＝スロット1そのもの）
    //   2回 -> スロット2 = クリップボード。CCする前のクリップボード内容へ戻す
    //   3回以上 -> 同様にその番号のスロットへ（スロット1は変えない）

    /// 今回のコピー連打が始まった時点（＝アプリが上書きする前）の
    /// クリップボード全体（テキスト・画像など全タイプ）
    private var preCopySnapshot: ClipboardSnapshot = []

    private func copyPressed() {
        if cCount == 0 {
            // アプリがクリップボードを書き換わる前の内容をここで控える
            preCopySnapshot = snapshotClipboard()
        }
        cCount += 1
        blog("C keyDown -> count=\(cCount)")

        copyBurstItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.commitCopy() }
        copyBurstItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + kPressWindow, execute: item)
    }

    private func commitCopy() {
        let slot = min(max(cCount, 1), kMaxSlot)
        cCount = 0

        guard let text = readClipboard() else { return }
        setSlot(slot, text)
        blog("slot \(slot) に保存: \(text.prefix(20))")

        if slot >= 2 {
            if preCopySnapshot.isEmpty {
                // 直前が本当に空だった → スロットに入れた内容で
                // クリップボードを汚さない（消して空のままにする）
                NSPasteboard.general.clearContents()
                blog("クリップボードを空に戻した")
            } else {
                // CC 直前のクリップボード（テキストだけでなく
                // 画像などの項目も含めて）をそのまま復元する
                restoreClipboard(preCopySnapshot)
                blog("クリップボードを CC 直前の内容へ戻した")
            }
        }
    }

    // ---- ペースト ----
    //
    // こちらも押し切ってから判定。VV と VVV を区別するため、
    // 最後の押しから kPressWindow 待ってからスロットを決める。

    private func pastePressed() -> Unmanaged<CGEvent>? {
        let t = now()
        if t - lastV > kPressWindow {
            vCount = 1
            swallowVRelease = true
        } else {
            vCount += 1
        }
        lastV = t
        blog("V keyDown -> count=\(vCount)")

        pasteBurstItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.commitPaste() }
        pasteBurstItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + kPressWindow, execute: item)

        return nil // もともとの Cmd+V は止める（コミット時に打ち直す）
    }

    private func commitPaste() {
        let slot = min(max(vCount, 1), kMaxSlot)
        vCount = 0
        swallowVRelease = false
        blog("paste commit -> slot \(slot)")

        if slot >= 2 {
            pasteSlot(slot)
        } else {
            // スロット1 = システムのクリップボードそのもの。常に通常ペースト
            injectCmdV()
        }
    }

    private func pasteSlot(_ slot: Int) {
        guard let text = slotText(slot) else {
            // 空スロットへのペーストは何もしない（誤って中身を出すことがないよう）
            blog("slot \(slot) は空 → ペーストしない")
            return
        }

        // ペーストでクリップボードを上書きする前全体を控えておく
        let snapshot = snapshotClipboard()
        writeClipboard(text)
        injectCmdV()

        // ペースト後、クリップボードを貼付直前の内容へ戻す
        // （テキストだけでなく画像などの項目もそのまま復元する）
        restoreItem?.cancel()
        let item = DispatchWorkItem {
            if snapshot.isEmpty {
                NSPasteboard.general.clearContents()
            } else {
                restoreClipboard(snapshot)
            }
        }
        restoreItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + kRestoreDelay, execute: item)
    }

    private func injectCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(kUserDataField, value: kSelfTag)
        up.setIntegerValueField(kUserDataField, value: kSelfTag)

        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}

// C 関数ポインタとして渡すコールバック（変数をキャプチャしてはいけない）
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let copyman = CopymanController.shared
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // タイムアウト等で無効化されたら再開する
        if let tap = copyman.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    return copyman.handle(type: type, event: event)
}

// MARK: - メニューバー

func preview(_ text: String, width: Int = 32) -> String {
    let oneLine = text.split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
    if oneLine.count > width {
        return String(oneLine.prefix(width)) + "…"
    }
    return oneLine
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let copyman = CopymanController.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        // メニューバーアイコン（.bundle 内 MenuBarIcon.pdf = テンプレート画像）
        // が見つからない場合のために絵文字フォールバックも用意しておく
        var menuBarIcon: NSImage?
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            menuBarIcon = img
        }

        copyman.onTrustedChange = { [weak self] trusted in
            guard let button = self?.statusItem.button else { return }
            if let icon = menuBarIcon {
                button.image = icon
                button.image?.isTemplate = true
                button.title = trusted ? "" : "⚠️"
            } else {
                button.image = nil
                button.title = trusted ? "📋" : "📋⚠️"
            }
        }

        if !copyman.startTap() {
            // 許可が付与されるのを待ち、付与されたら自动でタップを開始する
            copyman.startTrustPolling()

            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "アクセシビリティの許可が必要です"
            alert.informativeText = """
            システム設定 > プライバシーとセキュリティ > アクセシビリティ で \
            「CC&VV」をオンにしてください。オンになれば再起動なしで有効になります。
            （現在「拒否」になっている場合は、一度オフ/オンにするか、− で削除後に再追加してください）
            """
            alert.addButton(withTitle: "アクセシビリティ設定を開く")
            alert.addButton(withTitle: "あとで")
            if alert.runModal() == .alertFirstButtonReturn {
                openAccessibilitySettings()
            }
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // メニューを開いたときにスロット一覧を作り直す
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !copyman.isTrusted {
            let warn = NSMenuItem(
                title: "⚠️ アクセシビリティ権限がありません",
                action: #selector(openSettings(_:)), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        // スロット1＝システムクリップボードそのもの（ライブの内容を表示）
        if let clip = readClipboard() {
            let item = NSMenuItem(
                title: "スロット1: \(preview(clip))（システムクリップボード）",
                action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if !(NSPasteboard.general.types ?? []).isEmpty {
            // テキストではないが項目はある（画像など）
            let item = NSMenuItem(
                title: "スロット1: （画像などの非テキスト内容）（システムクリップボード）",
                action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "スロット1: （空）", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        for slot in 2...kMaxSlot {
            let title: String
            if let text = copyman.slotText(slot) {
                title = "スロット\(slot): \(preview(text))（クリックでコピー）"
            } else {
                title = "スロット\(slot): （空）"
            }
            let item = NSMenuItem(title: title, action: #selector(copySlot(_:)), keyEquivalent: "")
            item.target = self
            item.tag = slot
            item.isEnabled = copyman.slotText(slot) != nil
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let about = NSMenuItem(
            title: "Cmd+C×N でスロットN保存 / Cmd+V×N でスロットN貼付",
            action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)

        menu.addItem(.separator())

        let clear = NSMenuItem(
            title: "🗑 全スロットをクリア（クリップボードも）",
            action: #selector(clearAllSlots(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let quit = NSMenuItem(title: "CC&VV を終了", action: #selector(quit(_:)), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func openSettings(_ sender: Any?) {
        openAccessibilitySettings()
    }

    @objc private func copySlot(_ sender: NSMenuItem) {
        if let text = copyman.slotText(sender.tag) {
            writeClipboard(text)
        }
    }

    @objc private func clearAllSlots(_ sender: Any?) {
        copyman.clearAll()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

// MARK: - 起動

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // Dock にアイコンを出さない
app.run()
