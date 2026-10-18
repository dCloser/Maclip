import AppKit
import Combine

/// User settings, saved in UserDefaults. AppDelegate applies changes as they happen.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: Self { self }
        var title: String { rawValue.capitalized }
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    /// Choices offered in the UI.
    static let historyDayOptions = [0, 1, 7, 30, 90, 365] // 0 = forever
    static let maxItemOptions = [25, 50, 100, 200, 500, 1000]

    /// Unpinned items older than this many days are removed. 0 keeps them forever.
    @Published var historyDays: Int { didSet { defaults.set(historyDays, forKey: Keys.historyDays) } }
    /// Maximum number of unpinned items kept.
    @Published var maxItems: Int { didSet { defaults.set(maxItems, forKey: Keys.maxItems) } }
    @Published var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    /// The global shortcut that opens the history panel.
    @Published var hotKey: KeyCombo {
        didSet { defaults.set(try? JSONEncoder().encode(hotKey), forKey: Keys.hotKey) }
    }

    /// True while the Preferences window is recording a new shortcut (the current one is
    /// suspended so pressing it gets recorded instead of opening the panel).
    @Published var isRecordingShortcut = false
    /// Set when macOS refuses to register `hotKey`.
    @Published var hotKeyProblem: String?

    var maxAge: TimeInterval? { historyDays > 0 ? TimeInterval(historyDays) * 86_400 : nil }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let historyDays = "historyDays", maxItems = "maxItems"
        static let appearance = "appearance", hotKey = "hotKeyCombo"
    }

    private init() {
        historyDays = defaults.object(forKey: Keys.historyDays) as? Int ?? 0
        maxItems = defaults.object(forKey: Keys.maxItems) as? Int ?? 100
        appearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init) ?? .system
        hotKey = defaults.data(forKey: Keys.hotKey).flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
            ?? .default
    }

    static func describeDays(_ days: Int) -> String {
        switch days {
        case 0: return "Forever"
        case 1: return "1 day"
        case 365: return "1 year"
        default: return "\(days) days"
        }
    }
}
