import AppKit
import SwiftUI

/// Non-activating floating panel that can take key focus so letter shortcuts work without stealing app focus.
final class TipPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Shows, positions and auto-hides the clipboard tip near the mouse pointer.
@MainActor
final class TipPanelController {
    private var panel: TipPanel?
    private var hideWork: DispatchWorkItem?
    private var isHovering = false

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(controller: ClipboardController) {
        let panel = panel ?? makePanel(controller: controller)
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        restartTimer()
    }

    func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if !hovering { restartTimer() } else { hideWork?.cancel() }
    }

    func restartTimer() {
        hideWork?.cancel()
        guard !isHovering else { return }
        let duration = max(1, UserDefaults.standard.double(forKey: Prefs.tipDuration))
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func makePanel(controller: ClipboardController) -> TipPanel {
        let panel = TipPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
                             styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let hosting = NSHostingController(rootView: TipView(controller: controller))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        panel.keyHandler = { [weak self] event in
            if event.keyCode == 53 { self?.hide(); return true } // Escape
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
            if let reduction = Reduction.allCases.first(where: { $0.key == key }) {
                if controller.canApply(reduction) { controller.reduce(reduction) } else { NSSound.beep() }
                return true
            }
            if key == "u", !controller.log.isEmpty { controller.undoLast(); return true }
            return false
        }
        return panel
    }

    /// Places the panel just below-right of the pointer, kept inside the visible screen area.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        var origin = NSPoint(x: mouse.x + 14, y: mouse.y - size.height - 14)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            if origin.y < visible.minY + 8 { origin.y = min(mouse.y + 14, visible.maxY - size.height - 8) }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
