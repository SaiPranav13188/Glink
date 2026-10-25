import AppKit
import GlinkCore
import PDFKit

/// `Glink --ephemeral --semantic-selftest`: builds a scanned (image-only) invoice PDF named scan_0042.pdf,
/// a screenshot with text, and a decoy note in a temp folder, indexes only that folder (in memory),
/// runs the plan's two example searches, prints JSON and quits.
@MainActor
enum SemanticSelfTest {
    static func run() {
        Task { @MainActor in
            let dir = FileManager.default.temporaryDirectory.appending(path: "glink-semantic-\(UUID().uuidString.prefix(6))")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            // A "scan": the invoice exists only as pixels, so finding it requires OCR.
            let invoice = render(lines: ["ACME SUPPLIES LTD.", "INVOICE #4471", "Date: 14 September 2026",
                                         "Bill to: Sai Pranav", "Ergonomic chair   x1   $340.00", "Total due: $340.00"])
            let pdf = PDFDocument()
            if let page = PDFPage(image: invoice) { pdf.insert(page, at: 0) }
            pdf.write(to: dir.appending(path: "scan_0042.pdf"))

            let shot = render(lines: ["Team standup", "Q4 product roadmap kickoff", "Launch window moves to November"])
            if let tiff = shot.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appending(path: "Screenshot 2026-10-21 at 09.14.png"))
            }
            try? "Banana bread: 3 ripe bananas, flour, sugar, walnuts.".write(to: dir.appending(path: "recipe.md"), atomically: true, encoding: .utf8)

            let worker = IndexWorker(modelContainer: DataStore.shared.container)
            let started = Date()
            for file in await worker.discover(folders: [dir.path]) { await worker.indexIfNeeded(path: file) }
            var out: [String: Any] = ["indexSeconds": (Date().timeIntervalSince(started) * 10).rounded() / 10,
                                      "chunks": await worker.chunkCount]
            for query in ["invoice from september", "roadmap kickoff"] {
                let t0 = Date()
                let hits = await worker.search(query)
                out[query] = ["ms": Int(Date().timeIntervalSince(t0) * 1000),
                              "hits": hits.map { "\(($0.path as NSString).lastPathComponent) (\(String(format: "%.2f", $0.score)))" }]
            }
            try? FileManager.default.removeItem(at: dir)
            let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data ?? Data(), as: UTF8.self))
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    static func render(lines: [String]) -> NSImage {
        let size = NSSize(width: 1200, height: 160 + lines.count * 70)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        for (i, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 80, y: size.height - 120 - CGFloat(i * 70)),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 40, weight: i < 2 ? .bold : .regular),
                                                     .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        return image
    }
}
