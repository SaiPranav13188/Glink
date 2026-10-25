import AppKit
import CoreServices
import Foundation
import GlinkCore
import IOKit.ps
import NaturalLanguage
import Observation
import PDFKit
import SwiftData
import Vision

/// Search your Mac by meaning: background indexing of text, PDFs and screenshots with on-device
/// NaturalLanguage embeddings and Vision OCR. The index never leaves the Mac.
@MainActor @Observable
final class SemanticIndexer {
    static let shared = SemanticIndexer()

    private(set) var isIndexing = false
    private(set) var isPausedForConditions = false
    private(set) var indexedFiles = 0
    private(set) var totalFiles = 0
    private(set) var currentFile: String?
    private(set) var chunkCount = 0
    private(set) var lastRun: Date?

    var progress: Double { totalFiles == 0 ? 0 : Double(indexedFiles) / Double(totalFiles) }

    @ObservationIgnored private var worker: IndexWorker?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: FolderWatcher?

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "semanticSearchEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "semanticSearchEnabled")
            newValue ? start() : stop()
        }
    }

    var userPaused: Bool {
        get { UserDefaults.standard.bool(forKey: "semanticIndexPaused") }
        set { UserDefaults.standard.set(newValue, forKey: "semanticIndexPaused") }
    }

    static let defaultFolders = ["Documents", "Desktop", "Downloads"].map { NSHomeDirectory() + "/" + $0 }

    var folders: [String] {
        get { UserDefaults.standard.stringArray(forKey: "semanticFolders") ?? Self.defaultFolders }
        set {
            UserDefaults.standard.set(newValue, forKey: "semanticFolders")
            if enabled { start() }
        }
    }

    /// Set by the panel on every keystroke: indexing yields while the user is typing in Glink.
    @ObservationIgnored var lastKeystroke = Date.distantPast

    func start() {
        guard enabled, !DataStore.isEphemeral else { return }
        let worker = self.worker ?? IndexWorker(modelContainer: DataStore.shared.container)
        self.worker = worker
        watcher?.stop()
        watcher = FolderWatcher(paths: folders) { [weak self] paths in
            Task { @MainActor in self?.reindex(paths: paths) }
        }
        runFullPass()
    }

    func stop() {
        runTask?.cancel()
        watcher?.stop()
        watcher = nil
        isIndexing = false
    }

    func runFullPass(extraFolders: [String] = []) {
        guard let worker else { return }
        runTask?.cancel()
        let folders = self.folders + extraFolders
        isIndexing = true
        runTask = Task { [weak self] in
            await worker.loadIndex()
            let files = await worker.discover(folders: folders)
            guard let self else { return }
            self.totalFiles = files.count
            self.indexedFiles = 0
            for file in files {
                if Task.isCancelled { break }
                while await self.shouldPause() {
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: .seconds(2))
                }
                self.currentFile = (file as NSString).lastPathComponent
                await worker.indexIfNeeded(path: file)
                self.indexedFiles += 1
                self.chunkCount = await worker.chunkCount
            }
            self.currentFile = nil
            self.isIndexing = false
            self.isPausedForConditions = false
            self.lastRun = Date()
            self.chunkCount = await worker.chunkCount
        }
    }

    /// FSEvents told us these changed: re-index just them.
    func reindex(paths: [String]) {
        guard let worker, enabled else { return }
        Task {
            for path in paths where !(await shouldPause()) {
                if FileManager.default.fileExists(atPath: path) { await worker.indexIfNeeded(path: path) }
                else { await worker.remove(path: path) }
            }
            chunkCount = await worker.chunkCount
        }
    }

    func search(_ query: String) async -> [SemanticHit] {
        guard enabled, let worker, query.count >= 3 else { return [] }
        return await worker.search(query)
    }

    func clearIndex() {
        runTask?.cancel()
        isIndexing = false
        let w = worker ?? IndexWorker(modelContainer: DataStore.shared.container)
        worker = w
        Task {
            await w.clear()
            chunkCount = 0
            indexedFiles = 0
            totalFiles = 0
        }
    }

    /// Pause when the user paused, when typing in Glink, or on battery below 20%.
    private func shouldPause() async -> Bool {
        let typing = Date().timeIntervalSince(lastKeystroke) < 1.5
        let pause = userPaused || typing || Self.lowBattery()
        isPausedForConditions = pause
        return pause
    }

    static func lowBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            let onBattery = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            if onBattery, let cap = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0,
               Double(cap) / Double(max) < 0.2 { return true }
        }
        return false
    }
}

/// Background worker: extraction, chunking, embedding, storage, and the in-memory vector cache.
@ModelActor
actor IndexWorker {
    private var index = VectorIndex(dimension: 512)
    private var loaded = false
    private var modified: [String: Date] = [:]
    private lazy var embedding: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)

    static let textTypes: Set<String> = ["txt", "md", "markdown", "rtf", "docx", "pdf"]
    static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]
    static let skipFragments = ["/Library/", "/node_modules/", "/.git/", ".app/", "/DerivedData/", "/.Trash/", "/build/"]

    var chunkCount: Int { index.count }

    func loadIndex() {
        guard !loaded else { return }
        loaded = true
        let chunks = (try? modelContext.fetch(FetchDescriptor<SemanticChunk>())) ?? []
        for c in chunks {
            let v = VectorMath.floats(c.vector)
            if index.dimension != v.count, index.count == 0 { index = VectorIndex(dimension: v.count) }
            index.add(.init(path: c.path, chunkIndex: c.chunkIndex, text: c.text), vector: v)
            modified[c.path] = c.modified
        }
    }

    func discover(folders: [String]) -> [String] {
        var out: [String] = []
        let fm = FileManager.default
        for folder in folders {
            guard let e = fm.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                let path = url.path
                if Self.skipFragments.contains(where: path.contains) { e.skipDescendants(); continue }
                let ext = url.pathExtension.lowercased()
                guard Self.textTypes.contains(ext) || Self.imageTypes.contains(ext) else { continue }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size > 0, size < 50_000_000 else { continue }
                out.append(path)
                if out.count >= 10_000 { return out }
            }
        }
        return out
    }

    /// Re-indexes a file only when it changed since the last pass.
    func indexIfNeeded(path: String) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else { return }
        if let known = modified[path], abs(known.timeIntervalSince(date)) < 1 { return }
        remove(path: path)
        let ext = (path as NSString).pathExtension.lowercased()
        let text = Self.imageTypes.contains(ext) ? Self.ocr(imageAt: URL(fileURLWithPath: path)) : Self.extractText(path: path, ext: ext)
        let name = (path as NSString).lastPathComponent
        modified[path] = date
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let embedding else { return }
        for chunk in TextChunker.chunks(of: text).prefix(200) {
            // The file name is embedded too, so "Q3 budget" still finds budget-q3.xlsx.md.
            guard let v = embedding.vector(for: name + ". " + chunk.text)?.map(Float.init) else { continue }
            if index.count == 0, index.dimension != v.count { index = VectorIndex(dimension: v.count) }
            index.add(.init(path: path, chunkIndex: chunk.index, text: chunk.text), vector: v)
            modelContext.insert(SemanticChunk(path: path, chunkIndex: chunk.index, text: chunk.text,
                                              vector: VectorMath.data(v), modified: date, kind: ext))
        }
        try? modelContext.save()
    }

    func remove(path: String) {
        index.remove(path: path)
        modified[path] = nil
        try? modelContext.delete(model: SemanticChunk.self, where: #Predicate { $0.path == path })
    }

    func clear() {
        index = VectorIndex(dimension: index.dimension)
        modified = [:]
        try? modelContext.delete(model: SemanticChunk.self)
        try? modelContext.save()
    }

    func search(_ query: String) -> [SemanticHit] {
        loadIndex()
        guard let v = embedding?.vector(for: query)?.map(Float.init) else { return [] }
        return HybridRanker.rank(query: query, index: index, similarities: index.similarities(to: v))
    }

    // MARK: Extraction

    static func extractText(path: String, ext: String) -> String? {
        let url = URL(fileURLWithPath: path)
        switch ext {
        case "txt", "md", "markdown":
            return try? String(contentsOf: url, encoding: .utf8)
        case "rtf":
            return try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                           documentAttributes: nil).string
        case "docx":
            return try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                                           documentAttributes: nil).string
        case "pdf":
            guard let doc = PDFDocument(url: url) else { return nil }
            let text = doc.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 { return text }
            // Scanned PDF with no text layer: OCR the first pages.
            var ocr: [String] = []
            for i in 0..<min(doc.pageCount, 5) {
                guard let page = doc.page(at: i) else { continue }
                let image = page.thumbnail(of: CGSize(width: 1700, height: 2200), for: .mediaBox)
                if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let t = recognize(cg) { ocr.append(t) }
            }
            return ocr.joined(separator: "\n")
        default:
            return nil
        }
    }

    static func ocr(imageAt url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return recognize(image)
    }

    static func recognize(_ image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// FSEvents watcher for the indexed folders; reports changed file paths in batches.
final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let handler: @Sendable ([String]) -> Void

    init(paths: [String], handler: @escaping @Sendable ([String]) -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfPaths = unsafeBitCast(paths, to: NSArray.self)
            let list = (0..<count).compactMap { cfPaths[$0] as? String }
                .filter { !IndexWorker.skipFragments.contains(where: $0.contains) && !($0 as NSString).lastPathComponent.hasPrefix(".") }
            if !list.isEmpty { watcher.handler(list) }
        }
        stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 3.0,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
