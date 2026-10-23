import SwiftUI

struct ClipboardHistoryView: View {
    let model: PanelViewModel
    @Namespace private var zoomNamespace
    @State private var zoomed = true

    private var route: ClipboardRouteModel { model.clipboard }

    var body: some View {
        let sections = model.sections
        let entry = route.entry(for: model.selectedItem)
        Group {
            if sections.isEmpty {
                EmptyStateView(
                    symbol: "doc.on.clipboard",
                    title: model.query.isEmpty ? "Your clipboard history is empty" : "No matches",
                    message: model.query.isEmpty
                        ? "Copy some text, a link or an image and it shows up here. Password-manager items are never saved."
                        : "Nothing you've copied matches “\(model.query)”."
                )
            } else {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ResultsList(model: model, sections: sections, thumbnailNamespace: zoomNamespace)
                            .frame(width: 300)
                        Divider()
                        detail(entry)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    // The image preview flies out of the row's thumbnail into the detail pane.
                    if let entry, entry.kind == .image, let image = IconCache.shared.clipboardThumbnail(id: entry.id, data: { entry.imageData }) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: zoomed ? 8 : 5, style: .continuous))
                            .shadow(color: .black.opacity(zoomed ? 0.18 : 0), radius: 10, y: 4)
                            .matchedGeometryEffect(id: zoomed ? "pane" : "thumb-clip:\(entry.id.uuidString)", in: zoomNamespace, isSource: false)
                            .allowsHitTesting(false)
                            .id(entry.id)
                            .transition(.opacity)
                    }
                }
            }
        }
        .onChange(of: model.selectedID) { replayZoom() }
    }

    private func replayZoom() {
        guard !Motion.isReduced, !Motion.isOff else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { zoomed = false }
        DispatchQueue.main.async {
            withAnimation(Motion.smooth) { zoomed = true }
        }
    }

    @ViewBuilder
    private func detail(_ entry: ClipboardEntry?) -> some View {
        if let entry {
            VStack(spacing: 0) {
                preview(entry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)
                Divider()
                metadata(entry)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .id(entry.id)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func preview(_ entry: ClipboardEntry) -> some View {
        switch entry.kind {
        case .image:
            // Source frame for the zooming image overlay.
            Color.clear.matchedGeometryEffect(id: "pane", in: zoomNamespace, isSource: true)
        case .file:
            VStack(spacing: 10) {
                ItemIconView(icon: .path(entry.filePaths.first ?? "/"), size: 72)
                ForEach(entry.filePaths.prefix(4), id: \.self) { path in
                    Text((path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        case .color:
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: entry.text ?? "") ?? .gray)
                    .frame(width: 120, height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.1)))
                Text(entry.text ?? "").font(.system(size: 15, weight: .medium, design: .monospaced))
            }
        case .link:
            VStack(spacing: 10) {
                SymbolTile(symbol: "link", tint: .blue, size: 44)
                Text(URL(string: entry.text ?? "")?.host() ?? "")
                    .font(.system(size: 15, weight: .semibold))
                Text(entry.text ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        case .text:
            ScrollView {
                Text(entry.text ?? "")
                    .font(looksLikeCode(entry.text ?? "") ? Typography.mono(1) : .system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
        }
    }

    private func metadata(_ entry: ClipboardEntry) -> some View {
        var rows: [(String, String)] = []
        rows.append(("Application", entry.sourceAppName ?? "Unknown"))
        rows.append(("Content type", entry.kind.title))
        switch entry.kind {
        case .image: rows.append(("Dimensions", "\(entry.imageWidth) × \(entry.imageHeight)"))
        case .file: rows.append(("Items", "\(entry.filePaths.count)"))
        default:
            let text = entry.text ?? ""
            rows.append(("Characters", text.count.formatted()))
            rows.append(("Words", text.split { $0.isWhitespace || $0.isNewline }.count.formatted()))
        }
        rows.append(("Copied", entry.createdAt.formatted(date: .abbreviated, time: .shortened)))
        return VStack(spacing: 5) {
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1).monospacedDigit()
                }
                .font(.system(size: 12))
            }
        }
    }

    private func looksLikeCode(_ s: String) -> Bool {
        let markers = ["{", "}", ";", "=>", "func ", "def ", "import ", "</", "const ", "let "]
        return markers.filter { s.contains($0) }.count >= 2
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = Double((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(v & 0xFF) / 255 : 1
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
