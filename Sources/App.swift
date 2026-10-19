import SwiftUI
import AppKit

/// Entry point: a menu-bar-only app whose icon reflects what is on the clipboard.
@main
struct ClipPeekQueueMiniApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = ClipboardController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image(systemName: controller.summary.kind.symbol)
        }
    }
}

/// Starts clipboard monitoring and hotkeys once AppKit has finished launching.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in ClipboardController.shared.start() }
    }
}

/// Opens the external donation page.
enum Support {
    static func openDonation() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
