import AppKit

/// The standard macOS About panel (icon, name, version, copyright) with a short description
/// of Maclip as its credits.
@MainActor
enum About {
    static func show() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits(),
            .applicationName: "Maclip",
            .applicationIcon: NSApp.applicationIconImage as Any,
        ])
    }

    private static func credits() -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let bold = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let shortcut = Preferences.shared.hotKey.title

        let text = NSMutableAttributedString()
        func add(_ string: String, _ font: NSFont = body, color: NSColor = .labelColor) {
            text.append(NSAttributedString(string: string, attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
            ]))
        }
        add("Your clipboard history, one shortcut away.\n", bold)
        add("Press \(shortcut) in any app to search the text and images you've copied, "
            + "then paste one right where you were typing.\n")
        add("Private by design: ", bold)
        add("your history stays on this Mac. Nothing is uploaded or tracked.", color: .secondaryLabelColor)
        return text
    }
}
