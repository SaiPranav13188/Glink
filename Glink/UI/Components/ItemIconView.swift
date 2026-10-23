import AppKit
import SwiftUI

/// In-memory icon cache so scrolling and typing never re-hit the disk.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() { cache.countLimit = 600 }

    func icon(forPath path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 64, height: 64)
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    func clipboardThumbnail(id: UUID, data: () -> Data?) -> NSImage? {
        let key = "clip-\(id.uuidString)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = data(), let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    func clear() { cache.removeAllObjects() }
}

struct ItemIconView: View {
    let icon: ItemIcon
    var size: CGFloat = 24

    /// Icons are decorative: the row or label next to them carries the meaning.
    var body: some View {
        content.accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch icon {
        case .path(let path):
            Image(nsImage: IconCache.shared.icon(forPath: path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case .symbol(let name, let tint):
            SymbolTile(symbol: name, tint: tint.color, size: size)
        case .clipboardImage(let id):
            if let image = IconCache.shared.clipboardThumbnail(id: id, data: { ClipboardStore.shared.imageData(for: id) }) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                SymbolTile(symbol: "photo", tint: .orange, size: size)
            }
        case .glink:
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: size, height: size)
        }
    }
}

/// A Raycast-style command icon: white glyph on a softly lit, colored rounded square.
struct SymbolTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: symbol).accessibilityHidden(true)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
            )
            .frame(width: size, height: size)
    }
}
