import SwiftUI
import ImageIO
import MaclipCore

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var model: PanelModel
    let controller: PanelController
    @FocusState private var searchFocused: Bool

    private var items: [ClipItem] { store.displayItems(matching: model.query) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if items.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: 400, height: 460)
        .background(VisualEffect())
        .onChange(of: model.openToken) { searchFocused = true }
        .onChange(of: model.query) { model.selectedID = items.first?.id }
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Maclip").font(.headline)
                Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear all") { controller.clearAll() }
                    .buttonStyle(.borderless)
                    .help("Remove everything except pinned items")
                    .disabled(!store.items.contains { !$0.pinned })
            }
            // Search bar: focused when the panel opens, so you can type straight away.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search text and images", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(searchFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.1)))
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(model.query.isEmpty ? "Nothing copied yet" : "No matches")
                .foregroundStyle(.secondary)
            if model.query.isEmpty {
                Text("Copy text or an image and it will show up here.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipRow(item: item,
                                thumbnail: item.isImage ? Thumbnails.shared.image(for: item, in: store) : nil,
                                index: index,
                                isSelected: item.id == (model.selectedID ?? items.first?.id),
                                isHovered: item.id == model.hoveredID,
                                controller: controller)
                            .id(item.id)
                            .onHover { inside in
                                if inside { model.hoveredID = item.id }
                                else if model.hoveredID == item.id { model.hoveredID = nil }
                            }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selectedID) {
                if let id = model.selectedID { proxy.scrollTo(id) }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !model.accessibilityTrusted {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Auto-paste needs Accessibility access. Until then, choosing an item copies it; press ⌘V yourself.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Grant…") { controller.grantAccessibility() }
                        .buttonStyle(.link)
                }
                .font(.caption)
            }
            Text("↑↓ select · ↩ paste · ⌥↩ copy · ⌘1–9 pick · ⌘P pin · ⌘⌫ delete · esc close")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let thumbnail: NSImage?
    let index: Int
    let isSelected: Bool
    let isHovered: Bool
    let controller: PanelController

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                if item.isImage {
                    Group {
                        if let thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 90, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text(preview)
                        .font(.system(size: 13))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 6) {
                    if index < 9 { Text("⌘\(index + 1)") }
                    Text(item.date, style: .relative) + Text(" ago")
                    if item.isImage {
                        Text("· " + item.text)
                    } else if lineCount > 1 {
                        Text("· \(lineCount) lines")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                Button { controller.togglePin(item) } label: {
                    Image(systemName: item.pinned ? "pin.fill" : "pin")
                        .foregroundStyle(item.pinned ? Color.accentColor : .secondary)
                }
                .help(item.pinned ? "Unpin (⌘P)" : "Pin (⌘P)")
                .opacity(item.pinned || isSelected || isHovered ? 1 : 0)

                Button { controller.delete(item) } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }
                .help("Delete (⌘⌫)")
                .opacity(isSelected || isHovered ? 1 : 0)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.22)
                      : isHovered ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { controller.choose(item) }
    }

    /// Only the start of very long items is rendered, with leading blank lines dropped.
    private var preview: String {
        let head = item.text.prefix(600)
        let trimmed = head.drop { $0 == "\n" || $0 == "\r" || $0 == " " || $0 == "\t" }
        return String(trimmed)
    }

    private var lineCount: Int {
        item.text.prefix(100_000).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }
}

/// Small, cached previews of image items so the list doesn't decode full-size
/// screenshots on every redraw.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSString, NSImage>()

    func image(for item: ClipItem, in store: HistoryStore) -> NSImage? {
        guard let file = item.imageFile else { return nil }
        if let cached = cache.object(forKey: file as NSString) { return cached }
        guard let url = store.imageURL(for: item),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        cache.setObject(image, forKey: file as NSString)
        return image
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
