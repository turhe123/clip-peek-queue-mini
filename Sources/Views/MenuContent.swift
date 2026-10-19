import SwiftUI

/// Menu shown from the menu-bar icon: live clipboard summary plus the main commands.
struct MenuContent: View {
    @ObservedObject var controller: ClipboardController

    var body: some View {
        Text(controller.summary.title)
        if !controller.summary.typeNames.isEmpty {
            Text(controller.summary.typeNames.prefix(4).joined(separator: ", ")
                 + (controller.summary.typeNames.count > 4 ? " +\(controller.summary.typeNames.count - 4)" : ""))
        }
        Divider()
        Button("Inspect Clipboard  \(Prefs.shortcutText(modsKey: Prefs.inspectModifiers, nameKey: Prefs.inspectKeyName))") {
            controller.inspect()
        }
        Button("Paste as Plain Text  \(Prefs.shortcutText(modsKey: Prefs.pasteModifiers, nameKey: Prefs.pasteKeyName))") {
            // Give the menu time to close so focus returns to the previous app before pasting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { controller.pasteAsPlainText() }
        }
        Button("Undo Last Reduction") { controller.undoLast() }
            .disabled(controller.log.isEmpty)
        if !controller.log.isEmpty {
            Menu("Recent Reductions") {
                ForEach(controller.log) { entry in
                    Button("Undo \(entry.reduction.title) — \(entry.date.formatted(date: .omitted, time: .shortened))") {
                        controller.undo(entry)
                    }
                }
            }
        }
        Divider()
        Button("Settings…") { SettingsWindow.show() }
            .keyboardShortcut(",")
        Button("Support / Donate ❤️") { Support.openDonation() }
        Divider()
        Button("Quit ClipPeekQueueMini") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
