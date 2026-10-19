import SwiftUI
import ServiceManagement
import ApplicationServices

/// Hosts the settings view in a regular AppKit window (the app has no Dock icon).
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "ClipPeekQueueMini Settings"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Preferences: hotkeys, tip duration, auto-reduce with excluded apps, launch at login and permissions.
struct SettingsView: View {
    @AppStorage(Prefs.tipDuration) private var tipDuration = 5.0
    @AppStorage(Prefs.autoReduce) private var autoReduce = false
    @AppStorage(Prefs.excludedApps) private var excludedApps = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var axTrusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("Hotkeys") {
                HotKeyRecorder(title: "Inspect clipboard", codeKey: Prefs.inspectKeyCode,
                               modsKey: Prefs.inspectModifiers, nameKey: Prefs.inspectKeyName)
                HotKeyRecorder(title: "Paste as plain text", codeKey: Prefs.pasteKeyCode,
                               modsKey: Prefs.pasteModifiers, nameKey: Prefs.pasteKeyName)
            }
            Section("Tip") {
                Stepper("Show tip for \(Int(tipDuration)) seconds", value: $tipDuration, in: 2...20, step: 1)
            }
            Section("Automatic reduction") {
                Toggle("Reduce every copy to plain text", isOn: $autoReduce)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Disabled in these apps (bundle IDs, one per line)")
                        Spacer()
                        Menu("Add App") {
                            ForEach(runningApps, id: \.self) { id in
                                Button(id) { addExcluded(id) }
                            }
                        }
                        .fixedSize()
                    }
                    TextEditor(text: $excludedApps)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 70)
                }
                .disabled(!autoReduce)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                HStack {
                    Label(axTrusted ? "Accessibility access granted" : "Accessibility not granted — auto-paste disabled",
                          systemImage: axTrusted ? "checkmark.shield" : "exclamationmark.shield")
                        .foregroundStyle(axTrusted ? .green : .orange)
                    Spacer()
                    if !axTrusted {
                        Button("Grant…") { ClipboardController.requestAccessibility() }
                    }
                }
            }
            Section {
                HStack {
                    Text("ClipPeekQueueMini is free and open source.")
                    Spacer()
                    Button("Support / Donate ❤️") { Support.openDonation() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            axTrusted = AXIsProcessTrusted()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var runningApps: [String] {
        let ids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
        return Array(Set(ids)).sorted()
    }

    private func addExcluded(_ id: String) {
        guard !Prefs.excludedBundleIDs.contains(id) else { return }
        excludedApps = (excludedApps.isEmpty || excludedApps.hasSuffix("\n") ? excludedApps : excludedApps + "\n") + id
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Click-to-record control that captures a key combination and re-registers the global hotkeys.
struct HotKeyRecorder: View {
    let title: String
    let codeKey: String
    let modsKey: String
    let nameKey: String
    @State private var recording = false
    @State private var monitor: Any?
    @State private var display = ""

    var body: some View {
        LabeledContent(title) {
            Button(recording ? "Type shortcut… (Esc to cancel)" : display) {
                recording ? stop() : start()
            }
            .monospaced()
        }
        .onAppear { display = Prefs.shortcutText(modsKey: modsKey, nameKey: nameKey) }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            let mods = HotKeyCenter.carbonModifiers(event.modifierFlags)
            guard !event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
                NSSound.beep()
                return nil
            }
            var name = event.charactersIgnoringModifiers?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty { name = event.keyCode == 49 ? "Space" : "#\(event.keyCode)" }
            let defaults = UserDefaults.standard
            defaults.set(Int(event.keyCode), forKey: codeKey)
            defaults.set(mods, forKey: modsKey)
            defaults.set(name, forKey: nameKey)
            display = Prefs.shortcutText(modsKey: modsKey, nameKey: nameKey)
            ClipboardController.shared.registerHotKeys()
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
