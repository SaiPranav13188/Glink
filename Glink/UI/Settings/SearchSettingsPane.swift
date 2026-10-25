import AppKit
import SwiftUI

/// Settings › Search & Suggestions.
struct SearchSettingsPane: View {
    private var indexer: SemanticIndexer { SemanticIndexer.shared }
    @State private var enabled = SemanticIndexer.shared.enabled
    @State private var paused = SemanticIndexer.shared.userPaused
    @State private var folders = SemanticIndexer.shared.folders
    @AppStorage("suggestionsEnabled") private var suggestions = true
    @State private var confirmClear = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Toggle("Search my files by meaning", isOn: $enabled)
                    .onChange(of: enabled) { indexer.enabled = enabled }
                if enabled {
                    VStack(alignment: .leading, spacing: 6) {
                        if indexer.isIndexing {
                            ProgressView(value: indexer.progress) {
                                Text(indexer.isPausedForConditions ? "Paused" : "Indexing \(indexer.indexedFiles) of \(indexer.totalFiles) files")
                            } currentValueLabel: {
                                Text(indexer.currentFile ?? "").lineLimit(1).truncationMode(.middle)
                            }
                        } else {
                            Label("\(indexer.chunkCount) passages indexed" + (indexer.lastRun.map { " · updated \($0.formatted(.relative(presentation: .named)))" } ?? ""),
                                  systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .transition(.opacity)
                    Toggle("Pause indexing", isOn: $paused)
                        .onChange(of: paused) { indexer.userPaused = paused }
                    HStack {
                        Button("Re-index Now") { indexer.runFullPass() }
                        Button("Clear Index…", role: .destructive) { confirmClear = true }
                    }
                }
            } header: {
                Text("Search by meaning")
            } footer: {
                Text("Glink reads text, PDFs (including scans) and screenshots in the folders below and understands them with Apple's on-device NaturalLanguage and Vision frameworks. The index never leaves your Mac. Indexing pauses while you type in Glink and on battery below 20%.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if enabled {
                Section("Folders") {
                    ForEach(folders, id: \.self) { folder in
                        HStack {
                            Image(systemName: "folder").foregroundStyle(.secondary).accessibilityHidden(true)
                            Text((folder as NSString).abbreviatingWithTildeInPath)
                            Spacer()
                            Button {
                                folders.removeAll { $0 == folder }
                                indexer.folders = folders
                            } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(folder)")
                        }
                    }
                    Button("Add Folder…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = true
                        guard panel.runModal() == .OK else { return }
                        folders += panel.urls.map(\.path).filter { !folders.contains($0) }
                        indexer.folders = folders
                    }
                }
            }

            Section {
                Toggle("Show suggestions when the search field is empty", isOn: $suggestions)
                Button("Reset Learning…") { confirmReset = true }
            } header: {
                Text("Suggestions")
            } footer: {
                Text("Glink learns which results you use at which times and with which apps, and explains each suggestion. This stays on your Mac.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .motion(Motion.smooth, value: enabled)
        .confirmationDialog("Clear the search index?", isPresented: $confirmClear) {
            Button("Clear Index", role: .destructive) { indexer.clearIndex() }
        } message: { Text("Glink will re-index your folders the next time indexing runs.") }
        .confirmationDialog("Reset what Glink has learned?", isPresented: $confirmReset) {
            Button("Reset Learning", role: .destructive) { SuggestionsEngine.resetLearning() }
        } message: { Text("Suggestions start fresh. Your clipboard, snippets and settings aren't affected.") }
    }
}
