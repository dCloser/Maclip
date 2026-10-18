import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class PreferencesController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let onClearHistory: () -> Void

    init(onClearHistory: @escaping () -> Void) {
        self.onClearHistory = onClearHistory
    }

    func show() {
        if window == nil {
            let view = PreferencesView(prefs: .shared, onClearHistory: onClearHistory)
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "Maclip Preferences"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(window.contentView!.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        Preferences.shared.isRecordingShortcut = false
        window = nil
    }
}

private struct PreferencesView: View {
    @ObservedObject var prefs: Preferences
    let onClearHistory: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var trusted = Paster.isTrusted
    @State private var confirmClear = false
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("History") {
                Picker("Keep history for", selection: $prefs.historyDays) {
                    ForEach(Preferences.historyDayOptions, id: \.self) { Text(Preferences.describeDays($0)).tag($0) }
                }
                Picker("Items to keep", selection: $prefs.maxItems) {
                    ForEach(Preferences.maxItemOptions, id: \.self) { Text("\($0) items").tag($0) }
                }
                HStack {
                    Text("Pinned items are always kept and don't count toward the limit.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History…") { confirmClear = true }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $prefs.appearance) {
                    ForEach(Preferences.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Keyboard Shortcuts") {
                LabeledContent("Open Maclip") {
                    HStack(spacing: 8) {
                        ShortcutRecorder(prefs: prefs)
                        if prefs.hotKey != .default {
                            Button("Reset") { prefs.hotKey = .default }
                        }
                    }
                }
                if let problem = prefs.hotKeyProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                DisclosureGroup("Shortcuts in the Maclip panel") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        ForEach(Self.panelShortcuts, id: \.0) { key, action in
                            GridRow {
                                Text(key).monospaced().foregroundStyle(.secondary)
                                Text(action)
                            }
                        }
                    }
                    .font(.callout)
                    .padding(.vertical, 4)
                }
            }

            Section("General") {
                Toggle("Launch Maclip at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Auto-paste") {
                    if trusted {
                        Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Enable…") {
                            if !Paster.requestTrust() { Paster.openAccessibilitySettings() }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(refresh) { _ in trusted = Paster.isTrusted }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { onClearHistory() }
        } message: {
            Text("Everything except pinned items is deleted. This can't be undone.")
        }
    }

    private static let panelShortcuts: [(String, String)] = [
        ("type", "Search"),
        ("↑ ↓", "Move the selection"),
        ("↩", "Paste the selected item"),
        ("⌥↩", "Copy without pasting"),
        ("⌘1–⌘9", "Paste item 1–9"),
        ("⌘P", "Pin or unpin"),
        ("⌘⌫", "Delete the item"),
        ("esc", "Clear the search, then close"),
    ]

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// A button that shows the current shortcut; click it, then press the new combination.
private struct ShortcutRecorder: View {
    @ObservedObject var prefs: Preferences
    @StateObject private var recorder = KeyRecorder()

    var body: some View {
        Button {
            recorder.isRecording ? recorder.stop() : recorder.start(prefs: prefs)
        } label: {
            Text(recorder.isRecording ? "Type a shortcut…" : prefs.hotKey.title)
                .frame(minWidth: 110)
                .foregroundStyle(recorder.isRecording ? Color.accentColor : .primary)
        }
        .help(recorder.isRecording ? "Press a key with ⌘, ⌃ or ⌥. Esc cancels."
                                   : "Click, then press a new shortcut")
        .onDisappear { recorder.stop() }
    }
}

@MainActor
private final class KeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?
    private weak var prefs: Preferences?

    func start(prefs: Preferences) {
        self.prefs = prefs
        isRecording = true
        prefs.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53, event.modifierFlags.intersection(KeyCombo.relevantFlags).isEmpty {
                self.stop() // Esc on its own cancels
            } else if let combo = KeyCombo(event: event) {
                self.prefs?.hotKey = combo
                self.stop()
            } else {
                NSSound.beep() // needs ⌘, ⌃ or ⌥
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        prefs?.isRecordingShortcut = false
    }
}
