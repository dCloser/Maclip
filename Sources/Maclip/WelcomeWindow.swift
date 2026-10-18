import AppKit
import SwiftUI
import Combine

/// Shown on first launch (and from the menu): explains what Maclip does and why it asks for
/// the Accessibility permission, before macOS shows its own prompt.
@MainActor
final class WelcomeController: NSObject, NSWindowDelegate {
    static let shownKey = "didShowWelcome"
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = WelcomeView(shortcut: Preferences.shared.hotKey.title) { [weak self] in self?.close() }
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: view)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(window.contentView!.fittingSize)
            window.center()
            self.window = window
        }
        UserDefaults.standard.set(true, forKey: Self.shownKey)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct WelcomeView: View {
    let shortcut: String
    let onDone: () -> Void
    @State private var trusted = Paster.isTrusted
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Maclip").font(.title2.bold())
                    Text("Your clipboard history, one shortcut away.").foregroundStyle(.secondary)
                }
            }

            Text("Maclip remembers the text and images you copy. Press **\(shortcut)** in any app to see them, pick one, and Maclip pastes it where you were typing. It lives in the menu bar under the clipboard icon.")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Auto-paste (optional)", systemImage: "keyboard").font(.headline)
                    Text("To paste for you, Maclip presses ⌘V in the app you were using. macOS only allows that after you turn Maclip on under **Privacy & Security → Accessibility**. Maclip uses this permission for nothing else, and your clipboard history never leaves your Mac.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Without it, choosing an item copies it and you press ⌘V yourself.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if trusted {
                        Label("Auto-paste is enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Enable Auto-Paste…") {
                            if !Paster.requestTrust() { Paster.openAccessibilitySettings() }
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(trusted ? "Get Started" : "Not Now") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onReceive(refresh) { _ in trusted = Paster.isTrusted }
    }
}
