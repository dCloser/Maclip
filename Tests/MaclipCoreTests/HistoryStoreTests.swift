import Foundation
import Testing
@testable import MaclipCore

@MainActor
struct HistoryStoreTests {
    @Test func newestFirstAndSkipsConsecutiveDuplicates() {
        let store = HistoryStore(fileURL: nil)
        #expect(store.add("one"))
        #expect(store.add("two"))
        #expect(!store.add("two"))
        #expect(store.items.map(\.text) == ["two", "one"])
    }

    @Test func recopyMovesExistingItemToTop() {
        let store = HistoryStore(fileURL: nil)
        store.add("a"); store.add("b"); store.add("c")
        let idOfA = store.items.last!.id
        store.add("a")
        #expect(store.items.map(\.text) == ["a", "c", "b"])
        #expect(store.items.first!.id == idOfA)
    }

    @Test func ignoresBlankAndOversizedText() {
        let store = HistoryStore(fileURL: nil, maxTextLength: 10)
        #expect(!store.add("   \n\t"))
        #expect(!store.add(String(repeating: "x", count: 11)))
        #expect(store.add("multi\nline"))
        #expect(store.items.count == 1)
    }

    @Test func capEvictsOldestUnpinnedOnly() {
        let store = HistoryStore(fileURL: nil, maxUnpinned: 3)
        store.add("keep")
        store.togglePin(id: store.items[0].id)
        for i in 1...5 { store.add("item \(i)") }
        #expect(store.items.map(\.text) == ["item 5", "item 4", "item 3", "keep"])
    }

    @Test func pinnedFirstInDisplayAndSurvivesClear() {
        let store = HistoryStore(fileURL: nil)
        store.add("old pinned"); store.add("newer"); store.add("newest")
        store.togglePin(id: store.items.last!.id)
        #expect(store.displayItems().map(\.text) == ["old pinned", "newest", "newer"])
        store.clearUnpinned()
        #expect(store.items.map(\.text) == ["old pinned"])
    }

    @Test func filterIsCaseAndDiacriticInsensitive() {
        let store = HistoryStore(fileURL: nil)
        store.add("Café au lait"); store.add("tea"); store.add("CAFE menu")
        #expect(store.displayItems(matching: "cafe").map(\.text) == ["CAFE menu", "Café au lait"])
        #expect(store.displayItems(matching: "  ").count == 3)
    }

    @Test func removeDeletesSingleItem() {
        let store = HistoryStore(fileURL: nil)
        store.add("a"); store.add("b")
        store.remove(id: store.items[0].id)
        #expect(store.items.map(\.text) == ["a"])
    }

    @Test func imagesAreStoredDedupedAndDeletedWithTheirItem() throws {
        let store = HistoryStore(fileURL: nil)
        defer { try? FileManager.default.removeItem(at: store.imagesDirectory) }
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let other = Data([0x89, 0x50, 0x4E, 0x47, 9, 9, 9])

        #expect(store.addImage(png: png, width: 10, height: 20))
        #expect(!store.addImage(png: png, width: 10, height: 20))
        #expect(store.add("text in between"))
        #expect(store.addImage(png: other, width: 1, height: 1))
        #expect(store.addImage(png: png, width: 10, height: 20)) // re-copy moves it up
        #expect(store.items.map(\.text) == ["Image 10 × 20", "Image 1 × 1", "text in between"])

        let item = store.items[0]
        let url = try #require(store.imageURL(for: item))
        #expect(try Data(contentsOf: url) == png)
        #expect(store.displayItems(matching: "image").count == 2)

        store.remove(id: item.id)
        store.flush()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func textEqualToImageDescriptionIsNotADuplicate() {
        let store = HistoryStore(fileURL: nil)
        defer { try? FileManager.default.removeItem(at: store.imagesDirectory) }
        store.addImage(png: Data([1, 2, 3]), width: 2, height: 2)
        #expect(store.add("Image 2 × 2"))
        #expect(store.items.count == 2)
    }

    @Test func evictedAndClearedImagesLoseTheirFiles() throws {
        let store = HistoryStore(fileURL: nil, maxUnpinned: 1)
        defer { try? FileManager.default.removeItem(at: store.imagesDirectory) }
        store.addImage(png: Data([1]), width: 1, height: 1)
        let first = try #require(store.imageURL(for: store.items[0]))
        store.addImage(png: Data([2]), width: 1, height: 1)
        let second = try #require(store.imageURL(for: store.items[0]))
        store.clearUnpinned()
        store.flush()
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }

    @Test func persistsAcrossInstances() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaclipTests-\(UUID().uuidString)")
            .appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let first = HistoryStore(fileURL: url)
        first.add("hello"); first.add("world")
        first.togglePin(id: first.items[1].id)
        first.addImage(png: Data([7, 7]), width: 3, height: 4)
        first.flush()

        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)

        let second = HistoryStore(fileURL: url)
        #expect(second.items.map(\.text) == ["Image 3 × 4", "world", "hello"])
        #expect(second.items[2].pinned)
        #expect(try Data(contentsOf: #require(second.imageURL(for: second.items[0]))) == Data([7, 7]))
    }
}

@MainActor
struct HistoryLimitsTests {
    @Test func loweringTheItemLimitEvictsOldestUnpinned() {
        let store = HistoryStore(fileURL: nil, maxUnpinned: 10)
        store.add("pinned")
        store.togglePin(id: store.items[0].id)
        for i in 1...5 { store.add("item \(i)") }
        store.maxUnpinned = 2
        #expect(store.items.map(\.text) == ["item 5", "item 4", "pinned"])
        store.maxUnpinned = 10
        store.add("item 6")
        #expect(store.items.count == 4)
    }

    @Test func maxAgeRemovesOldUnpinnedItemsOnly() {
        let now = Date()
        let store = HistoryStore(fileURL: nil)
        store.add("ancient pinned", date: now.addingTimeInterval(-10 * 86_400))
        store.togglePin(id: store.items[0].id)
        store.add("old", date: now.addingTimeInterval(-3 * 86_400))
        store.add("recent", date: now.addingTimeInterval(-3_600))

        store.maxAge = 2 * 86_400
        #expect(store.items.map(\.text) == ["recent", "ancient pinned"])

        store.maxAge = nil
        store.add("older than limit but kept", date: now.addingTimeInterval(-30 * 86_400))
        #expect(store.items.count == 3)
    }

    @Test func expiredItemsArePurgedOnLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaclipTests-\(UUID().uuidString)")
            .appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = HistoryStore(fileURL: url)
        first.add("stale", date: Date().addingTimeInterval(-5 * 86_400))
        first.add("fresh")
        first.flush()

        let second = HistoryStore(fileURL: url, maxAge: 86_400)
        #expect(second.items.map(\.text) == ["fresh"])
    }
}
