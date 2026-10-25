import GlinkCore
import SwiftData
import SwiftUI

/// Settings › MCP Servers: connect servers so their tools become Glink commands.
struct MCPServersSettingsPane: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MCPServerEntry.createdAt) private var servers: [MCPServerEntry]
    @State private var adding = false
    @State private var pendingRisky: MCPServerEntry?
    @State private var riskyResult: MCPServerResult?
    private var manager: MCPClientManager { MCPClientManager.shared }

    var body: some View {
        Form {
            Section {
                if servers.isEmpty {
                    Text("No servers yet. Add one, or import a server from your existing MCP configs.")
                        .foregroundStyle(.secondary)
                }
                ForEach(servers) { server in serverRow(server) }
                HStack {
                    Button("Add Server…") { adding = true }
                    Menu("Import from Configs") {
                        let found = importable
                        if found.isEmpty { Text("No local stdio servers found") }
                        ForEach(Array(found.enumerated()), id: \.offset) { _, s in
                            Button("\(s.name) — \(s.source)") { add(name: s.name, command: s.command ?? "", args: s.args, env: s.env) }
                        }
                    }
                    .fixedSize()
                }
            } header: {
                Text("Servers")
            } footer: {
                Text("Before a server can be enabled, Glink runs its MCP security check. Grades D and F need your confirmation. Server processes stop when you disable them or quit Glink.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            let tools = manager.allTools
            if !tools.isEmpty {
                Section("Tool permissions") {
                    ForEach(tools) { tool in ToolPermissionRow(tool: tool) }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $adding) {
            AddServerSheet { name, command, args, env in add(name: name, command: command, args: args, env: env) }
        }
        .alert("Enable \(pendingRisky?.name ?? "") anyway?", isPresented: Binding(get: { pendingRisky != nil }, set: { if !$0 { pendingRisky = nil } })) {
            Button("Enable Anyway", role: .destructive) {
                if let s = pendingRisky { enable(s) }
                pendingRisky = nil
            }
            Button("Cancel", role: .cancel) { pendingRisky = nil }
        } message: {
            Text("This server scored \(riskyResult?.score ?? 0) (grade \(riskyResult?.letter ?? "?")). " +
                 (riskyResult?.findings.prefix(3).map(\.title).joined(separator: "; ") ?? ""))
        }
        .motion(Motion.smooth, value: servers.count)
    }

    private var importable: [MCPServerConfig] {
        let existing = Set(servers.map(\.name))
        let report = MCPConfigAnalyzer.scan()
        return report.results.map(\.raw).filter { $0.command != nil && $0.url == nil && !existing.contains($0.name) }
    }

    @ViewBuilder
    private func serverRow(_ server: MCPServerEntry) -> some View {
        HStack(spacing: 10) {
            stateDot(manager.state(of: server.id))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name)
                    Text(server.grade).font(.system(size: 11, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(gradeColor(server.grade).opacity(0.18)))
                }
                Text(([server.command] + server.args).joined(separator: " "))
                    .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if case .failed(let message) = manager.state(of: server.id) {
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if case .connected = manager.state(of: server.id) {
                    Text("\(manager.tools[server.id]?.count ?? 0) tools").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { server.enabled }, set: { on in on ? requestEnable(server) : disable(server) }))
                .labelsHidden()
                .toggleStyle(.switch)
            Button {
                disable(server)
                context.delete(server)
                try? context.save()
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(server.name)")
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func stateDot(_ state: MCPClientManager.State) -> some View {
        switch state {
        case .connecting: ProgressView().controlSize(.mini).frame(width: 10)
        case .connected: Circle().fill(.green).frame(width: 8, height: 8).accessibilityLabel("Connected")
        case .failed: Circle().fill(.red).frame(width: 8, height: 8).accessibilityLabel("Failed")
        case .disconnected: Circle().fill(Color.secondary.opacity(0.4)).frame(width: 8, height: 8).accessibilityLabel("Off")
        }
    }

    private func gradeColor(_ g: String) -> Color {
        switch g { case "A": .green; case "B": .teal; case "C": .yellow; case "D": .orange; case "F": .red; default: .gray }
    }

    private func add(name: String, command: String, args: [String], env: [String: String]) {
        let entry = MCPServerEntry(name: name, command: command, args: args,
                                   envText: env.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"))
        entry.grade = entry.securityResult.letter
        context.insert(entry)
        try? context.save()
    }

    private func requestEnable(_ server: MCPServerEntry) {
        let result = server.securityResult
        server.grade = result.letter
        if ["D", "F"].contains(result.letter) {
            riskyResult = result
            pendingRisky = server
        } else {
            enable(server)
        }
    }

    private func enable(_ server: MCPServerEntry) {
        server.enabled = true
        try? context.save()
        Task { await manager.connect(server) }
    }

    private func disable(_ server: MCPServerEntry) {
        server.enabled = false
        try? context.save()
        manager.disconnect(server.id)
    }
}

private struct ToolPermissionRow: View {
    let tool: MCPClientManager.ToolInfo
    @State private var override: Int = -1
    @State private var always = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.name)
                Text("\(tool.serverName) · detected: \(tool.classifiedRisk.title)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Risk", selection: $override) {
                Text("Automatic").tag(-1)
                ForEach(ToolRisk.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
            }
            .labelsHidden()
            .fixedSize()
            Toggle("Always allow", isOn: $always).toggleStyle(.checkbox)
        }
        .onAppear {
            let pref = MCPClientManager.shared.preference(server: tool.serverName, tool: tool.name)
            override = pref.riskOverride
            always = pref.alwaysAllow
        }
        .onChange(of: override) {
            MCPClientManager.shared.preference(server: tool.serverName, tool: tool.name).riskOverride = override
            DataStore.shared.save()
        }
        .onChange(of: always) {
            MCPClientManager.shared.preference(server: tool.serverName, tool: tool.name).alwaysAllow = always
            DataStore.shared.save()
        }
    }
}

private struct AddServerSheet: View {
    let onAdd: (String, String, [String], [String: String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var command = "npx"
    @State private var args = "-y\n@modelcontextprotocol/server-filesystem@2025.8.21\n~/Documents"
    @State private var env = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add MCP Server").font(.headline)
            Form {
                TextField("Name", text: $name, prompt: Text("filesystem"))
                TextField("Command", text: $command)
                VStack(alignment: .leading) {
                    Text("Arguments (one per line)").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $args).font(.body.monospaced()).frame(height: 70)
                }
                VStack(alignment: .leading) {
                    Text("Environment (KEY=VALUE per line)").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $env).font(.body.monospaced()).frame(height: 50)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    let argList = args.split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .map { $0.hasPrefix("~/") ? NSHomeDirectory() + $0.dropFirst() : $0 }
                    let envMap = env.split(whereSeparator: \.isNewline).reduce(into: [String: String]()) { out, line in
                        let p = line.split(separator: "=", maxSplits: 1).map(String.init)
                        if p.count == 2 { out[p[0]] = p[1] }
                    }
                    onAdd(name.isEmpty ? command : name, command, argList, envMap)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(command.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
