import Foundation
import Combine
import CryptoKit

public struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The copied text, or for images a short description such as "Image 1440 × 900".
    public var text: String
    public var date: Date
    public var pinned: Bool
    /// For images: the PNG's file name inside the store's images directory.
    public var imageFile: String?
    /// For images: SHA-256 of the PNG data, used to spot repeated copies.
    public var imageHash: String?

    public var isImage: Bool { imageFile != nil }

    public init(id: UUID = UUID(), text: String, date: Date = Date(), pinned: Bool = false,
                imageFile: String? = nil, imageHash: String? = nil) {
        self.id = id
        self.text = text
        self.date = date
        self.pinned = pinned
        self.imageFile = imageFile
        self.imageHash = imageHash
    }
}

/// The clipboard history. `items` is kept newest first; pinned items are never
/// evicted by the size cap or by `clearUnpinned()`. Image items keep their PNG data in
/// separate files next to the JSON history; those files are deleted with their items.
@MainActor
public final class HistoryStore: ObservableObject {
    @Published public private(set) var items: [ClipItem] = []

    /// Maximum number of unpinned items (text and images together). Pinned items do not count.
    /// Lowering it removes the oldest unpinned items straight away.
    public var maxUnpinned: Int {
        didSet {
            guard maxUnpinned != oldValue else { return }
            enforceCap()
            save()
        }
    }
    /// Unpinned items older than this many seconds are removed; nil keeps them forever.
    /// Checked when it changes, when something is copied, and on `purgeExpired()`.
    public var maxAge: TimeInterval? {
        didSet {
            guard maxAge != oldValue else { return }
            purgeExpired()
        }
    }
    /// Text longer than this (in UTF-16 units) is ignored, to keep the history file small.
    public let maxTextLength: Int
    /// Images whose PNG data is larger than this are ignored.
    public let maxImageBytes: Int
    public let imagesDirectory: URL

    private let fileURL: URL?
    private let saveQueue = DispatchQueue(label: "Maclip.save")

    public init(fileURL: URL?, imagesDirectory: URL? = nil, maxUnpinned: Int = 100,
                maxAge: TimeInterval? = nil,
                maxTextLength: Int = 1_000_000, maxImageBytes: Int = 25_000_000) {
        self.fileURL = fileURL
        self.imagesDirectory = imagesDirectory
            ?? fileURL?.deletingLastPathComponent().appendingPathComponent("images", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Maclip-\(UUID().uuidString)")
        self.maxUnpinned = maxUnpinned
        self.maxAge = maxAge
        self.maxTextLength = maxTextLength
        self.maxImageBytes = maxImageBytes
        load()
        purgeExpired()
    }

    /// `Application Support/Maclip/history.json` (inside the app's container when sandboxed).
    /// History saved by earlier builds, which used an `Application Support/ClipboardHistory`
    /// folder, is moved over the first time. For the sandboxed app, macOS first moves that
    /// folder into the container (see Support/container-migration.plist).
    public static var defaultFileURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Maclip", isDirectory: true)
        let legacy = base.appendingPathComponent("ClipboardHistory", isDirectory: true)
        if !fm.fileExists(atPath: dir.path), fm.fileExists(atPath: legacy.path) {
            do {
                try fm.moveItem(at: legacy, to: dir)
            } catch {
                NSLog("Maclip: could not move old history from %@: %@", legacy.path, String(describing: error))
            }
        }
        return dir.appendingPathComponent("history.json")
    }

    public func imageURL(for item: ClipItem) -> URL? {
        item.imageFile.map { imagesDirectory.appendingPathComponent($0) }
    }

    public static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Mutations

    /// Records newly copied text. Returns false if it was ignored (empty, too long,
    /// or identical to the newest item). Copying text that is already further down
    /// the list moves that entry to the top instead of creating a duplicate.
    @discardableResult
    public func add(_ text: String, date: Date = Date()) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf16.count <= maxTextLength else { return false }
        return insertOrPromote(where: { !$0.isImage && $0.text == text }, date: date) {
            ClipItem(text: text, date: date)
        }
    }

    /// Records a newly copied image, given as PNG data and its pixel size. Same rules as
    /// `add(_:)`: repeats of the newest item are ignored, older copies move to the top.
    @discardableResult
    public func addImage(png: Data, width: Int, height: Int, date: Date = Date()) -> Bool {
        guard !png.isEmpty, png.count <= maxImageBytes else { return false }
        let hash = Self.hash(of: png)
        return insertOrPromote(where: { $0.imageHash == hash }, date: date) {
            let id = UUID()
            let fileName = "\(id.uuidString).png"
            do {
                try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let url = imagesDirectory.appendingPathComponent(fileName)
                try png.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                NSLog("Maclip: could not save image: %@", String(describing: error))
                return nil
            }
            return ClipItem(id: id, text: "Image \(width) × \(height)", date: date,
                            imageFile: fileName, imageHash: hash)
        }
    }

    /// Moves an existing item to the top, as if it had just been copied again.
    public func moveToTop(id: UUID, date: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: i)
        item.date = date
        items.insert(item, at: 0)
        save()
    }

    public func remove(id: UUID) {
        discard(items.filter { $0.id == id })
        items.removeAll { $0.id == id }
        save()
    }

    public func togglePin(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
        enforceCap()
        save()
    }

    /// Removes unpinned items last copied more than `maxAge` ago (relative to `now`).
    public func purgeExpired(now: Date = Date()) {
        guard let maxAge else { return }
        let cutoff = now.addingTimeInterval(-maxAge)
        let expired = items.filter { !$0.pinned && $0.date < cutoff }
        guard !expired.isEmpty else { return }
        discard(expired)
        items.removeAll { !$0.pinned && $0.date < cutoff }
        save()
    }

    /// Like Windows' "Clear all": removes everything except pinned items.
    public func clearUnpinned() {
        discard(items.filter { !$0.pinned })
        items.removeAll { !$0.pinned }
        save()
    }

    // MARK: - Queries

    /// Items in display order: pinned first, then the rest, each group newest first.
    /// `query` filters case- and diacritic-insensitively; an empty query matches everything.
    /// Images match on their description, so "image" finds all of them.
    public func displayItems(matching query: String = "") -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = q.isEmpty ? items : items.filter {
            $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return matching.filter(\.pinned) + matching.filter { !$0.pinned }
    }

    // MARK: - Internals

    private struct Snapshot: Codable {
        var version = 1
        var items: [ClipItem]
    }

    private func insertOrPromote(where matches: (ClipItem) -> Bool, date: Date,
                                 makeNew: () -> ClipItem?) -> Bool {
        if let first = items.first, matches(first) { return false }
        let item: ClipItem
        if let existing = items.firstIndex(where: matches) {
            var moved = items.remove(at: existing)
            moved.date = date
            item = moved
        } else if let new = makeNew() {
            item = new
        } else {
            return false
        }
        items.insert(item, at: 0)
        enforceCap()
        save()
        purgeExpired(now: date)
        return true
    }

    private func enforceCap() {
        var unpinnedSeen = 0
        var evicted: [ClipItem] = []
        items.removeAll { item in
            guard !item.pinned else { return false }
            unpinnedSeen += 1
            if unpinnedSeen > maxUnpinned { evicted.append(item); return true }
            return false
        }
        discard(evicted)
    }

    /// Deletes the image files of items that are leaving the history.
    private func discard(_ removed: [ClipItem]) {
        let urls = removed.compactMap(imageURL(for:))
        guard !urls.isEmpty else { return }
        saveQueue.async {
            for url in urls { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            items = try JSONDecoder().decode(Snapshot.self, from: data).items
            // Drop images whose file has gone missing.
            items.removeAll { item in
                guard let url = imageURL(for: item) else { return false }
                return !FileManager.default.fileExists(atPath: url.path)
            }
            enforceCap()
        } catch {
            NSLog("Maclip: could not read %@: %@", fileURL.path, String(describing: error))
        }
    }

    private func save() {
        guard let fileURL else { return }
        let snapshot = Snapshot(items: items)
        saveQueue.async {
            do {
                let dir = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
                // Clipboard contents can be sensitive: keep the file private to this user.
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            } catch {
                NSLog("Maclip: could not save history: %@", String(describing: error))
            }
        }
    }

    /// Blocks until pending saves and file deletions are done. Used on quit and in tests.
    public func flush() {
        saveQueue.sync {}
    }
}
