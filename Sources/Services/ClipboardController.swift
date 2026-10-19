import AppKit
import ApplicationServices

/// A way of stripping the clipboard down to a single representation.
enum Reduction: String, CaseIterable, Identifiable {
    case plainText, firstFile, pngImage, singleLine

    var id: String { rawValue }
    var key: String {
        switch self {
        case .plainText: return "p"
        case .firstFile: return "f"
        case .pngImage: return "i"
        case .singleLine: return "t"
        }
    }
    var title: String {
        switch self {
        case .plainText: return "Plain Text"
        case .firstFile: return "First File Path"
        case .pngImage: return "PNG Image"
        case .singleLine: return "Trimmed Line"
        }
    }
}

/// A completed reduction plus the original pasteboard items needed to undo it.
struct ReductionLogEntry: Identifiable {
    let id = UUID()
    let reduction: Reduction
    let date = Date()
    let original: [[NSPasteboard.PasteboardType: Data]]
}

/// Owns clipboard state: polls for changes, performs reductions, keeps the undo log and pastes.
@MainActor
final class ClipboardController: ObservableObject {
    static let shared = ClipboardController()

    @Published private(set) var summary = ClipSummary()
    @Published private(set) var snapshot: ClipSnapshot?
    @Published private(set) var log: [ReductionLogEntry] = []
    @Published private(set) var isConverting = false
    @Published var notice: String?

    let tip = TipPanelController()
    private let pb = NSPasteboard.general
    private var lastChangeCount = -1
    private var ownChangeCount = -1
    private var timer: Timer?

    func start() {
        Prefs.registerDefaults()
        registerHotKeys()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            Task { @MainActor in ClipboardController.shared.poll() }
        }
    }

    func registerHotKeys() {
        let d = UserDefaults.standard
        HotKeyCenter.shared.register(id: 1, keyCode: d.integer(forKey: Prefs.inspectKeyCode),
                                     modifiers: d.integer(forKey: Prefs.inspectModifiers)) {
            Task { @MainActor in ClipboardController.shared.inspect() }
        }
        HotKeyCenter.shared.register(id: 2, keyCode: d.integer(forKey: Prefs.pasteKeyCode),
                                     modifiers: d.integer(forKey: Prefs.pasteModifiers)) {
            Task { @MainActor in ClipboardController.shared.pasteAsPlainText() }
        }
    }

    // MARK: Monitoring

    private func poll() {
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        summary = ClipboardInspector.summary(pb)
        guard count != ownChangeCount else { return }
        if tip.isVisible { refreshSnapshot() }
        if UserDefaults.standard.bool(forKey: Prefs.autoReduce) { autoReduce() }
    }

    /// Auto mode: reduce foreign copies to plain text, skipping concealed data, excluded apps and our own writes.
    private func autoReduce() {
        guard summary.kind == .richText, !ClipboardInspector.isConcealed(pb) else { return }
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           Prefs.excludedBundleIDs.contains(bundleID) { return }
        _ = reduce(.plainText)
    }

    // MARK: Inspection

    func inspect() {
        notice = nil
        refreshSnapshot()
        tip.show(controller: self)
    }

    /// Re-reads the pasteboard and decodes any image thumbnail in the background.
    func refreshSnapshot() {
        let snap = ClipboardInspector.snapshot(pb)
        snapshot = snap
        let source = snap.image
        guard let source else { return }
        let changeCount = snap.changeCount
        Task.detached(priority: .userInitiated) {
            let result = source.load().flatMap { ClipboardInspector.thumbnail(from: $0) }
            await MainActor.run {
                let controller = ClipboardController.shared
                guard let result, controller.snapshot?.changeCount == changeCount else { return }
                controller.snapshot?.thumbnail = result.0
                controller.snapshot?.pixelSize = result.1
            }
        }
    }

    func canApply(_ reduction: Reduction) -> Bool {
        guard let snap = snapshot else { return false }
        switch reduction {
        case .plainText, .singleLine: return snap.text != nil
        case .firstFile: return !snap.fileURLs.isEmpty
        case .pngImage: return snap.image != nil
        }
    }

    // MARK: Reductions

    /// Applies a reduction to the *current* pasteboard contents. Returns false if it could not be applied.
    @discardableResult
    func reduce(_ reduction: Reduction) -> Bool {
        let original = captureItems()
        switch reduction {
        case .plainText:
            guard let text = pb.string(forType: .string) else { return fail("There is no text on the clipboard.") }
            commit(reduction, original: original) { $0.setString(text, forType: .string) }
        case .singleLine:
            guard let text = pb.string(forType: .string) else { return fail("There is no text on the clipboard.") }
            let line = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            commit(reduction, original: original) { $0.setString(line, forType: .string) }
        case .firstFile:
            guard let url = ClipboardInspector.fileURLs(pb).first else { return fail("There are no files on the clipboard.") }
            commit(reduction, original: original) { $0.setString(url.path, forType: .string) }
        case .pngImage:
            guard let source = ClipboardInspector.imageSource(pb) else { return fail("There is no image on the clipboard.") }
            convertToPNG(source, original: original, startCount: pb.changeCount)
        }
        return true
    }

    /// PNG conversion runs off the main thread; if the clipboard changes meanwhile, we start over on the latest content.
    private func convertToPNG(_ source: ImageSource, original: [[NSPasteboard.PasteboardType: Data]], startCount: Int) {
        isConverting = true
        Task.detached(priority: .userInitiated) {
            let png = source.load().flatMap { ClipboardInspector.pngData(from: $0) }
            await MainActor.run {
                let controller = ClipboardController.shared
                controller.isConverting = false
                if controller.pb.changeCount != startCount {
                    controller.notice = "Clipboard changed during conversion; used the latest content."
                    controller.reduce(.pngImage)
                    return
                }
                guard let png else { controller.fail("The image could not be converted to PNG."); return }
                controller.commit(.pngImage, original: original) { $0.setData(png, forType: .png) }
            }
        }
    }

    private func commit(_ reduction: Reduction, original: [[NSPasteboard.PasteboardType: Data]],
                        write: (NSPasteboard) -> Void) {
        pb.clearContents()
        write(pb)
        markOwnChange()
        log.insert(ReductionLogEntry(reduction: reduction, original: original), at: 0)
        if log.count > 5 { log.removeLast(log.count - 5) }
        notice = "Reduced to \(reduction.title)."
        afterChange()
    }

    @discardableResult
    private func fail(_ message: String) -> Bool {
        notice = message
        NSSound.beep()
        if tip.isVisible { refreshSnapshot() }
        return false
    }

    // MARK: Undo

    func undoLast() {
        guard let entry = log.first else { return }
        undo(entry)
    }

    /// Restores the pasteboard items saved before the given reduction.
    func undo(_ entry: ReductionLogEntry) {
        pb.clearContents()
        let items = entry.original.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
        markOwnChange()
        log.removeAll { $0.id == entry.id }
        notice = "Restored the original clipboard."
        afterChange()
    }

    private func captureItems() -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { dict[type] = data } }
            return dict
        }
    }

    private func markOwnChange() {
        ownChangeCount = pb.changeCount
        lastChangeCount = ownChangeCount
        summary = ClipboardInspector.summary(pb)
    }

    private func afterChange() {
        if tip.isVisible {
            refreshSnapshot()
            tip.restartTimer()
        }
    }

    // MARK: Paste

    /// Reduces to plain text and sends ⌘V to the frontmost app, or explains how to grant Accessibility.
    func pasteAsPlainText() {
        guard reduce(.plainText) else { tip.show(controller: self); return }
        if AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Self.postCommandV() }
            return
        }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Prefs.explainedAccessibility) {
            defaults.set(true, forKey: Prefs.explainedAccessibility)
            explainAccessibility()
        }
        notice = "Plain text is ready. Press ⌘V to paste (Accessibility access is needed for auto-paste)."
        refreshSnapshot()
        tip.show(controller: self)
    }

    func explainAccessibility() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow ClipPeekQueueMini to paste for you"
        alert.informativeText = """
        To paste automatically, ClipPeekQueueMini sends a ⌘V keystroke to the frontmost app, \
        which macOS only allows with Accessibility access. Nothing else is read or recorded.

        Until access is granted, the clipboard is still reduced to plain text and you can press ⌘V yourself.
        """
        alert.addButton(withTitle: "Grant Access…")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { Self.requestAccessibility() }
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
