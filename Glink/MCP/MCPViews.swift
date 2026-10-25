import GlinkCore
import SwiftUI

/// Form generated from the tool's JSON schema, the permission sheet, and the result with its injection banner.
struct MCPToolView: View {
    @Bindable var run: MCPToolRunModel
    @FocusState private var focusedField: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let tool = run.tool {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(tool)
                        if run.fields.isEmpty {
                            Text("This tool takes no input. Press ↵ to run it.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        ForEach(run.fields) { field in fieldRow(field) }
                        if let error = run.formError {
                            Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange).font(.system(size: 12))
                                .transition(.opacity.combined(with: .offset(y: -4)))
                        }
                        result
                    }
                    .padding(18)
                }
                if let request = run.permission {
                    PermissionSheet(tool: tool, request: request, onAllowOnce: run.allowOnce, onAlways: run.allowAlways, onDeny: run.deny)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 10)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .motion(Motion.snappy, value: run.permission)
            .motion(Motion.smooth, value: run.phase)
            .motion(Motion.gentle, value: run.formError)
            .onAppear { focusedField = run.fields.first?.name }
        }
    }

    private func header(_ tool: MCPClientManager.ToolInfo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SymbolTile(symbol: "hammer.fill", tint: run.risk.needsPermission ? .orange : .teal, size: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name).font(.system(size: 15, weight: .semibold))
                Text(tool.description ?? tool.serverName).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer()
            RiskBadge(risk: run.risk)
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: ToolFormField) -> some View {
        let binding = Binding(get: { run.values[field.name] ?? "" }, set: { run.values[field.name] = $0 })
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(field.title).font(.system(size: 12, weight: .medium))
                if field.required { Text("required").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            switch field.kind {
            case .toggle:
                Toggle(field.help ?? field.title, isOn: Binding(get: { binding.wrappedValue == "true" },
                                                              set: { binding.wrappedValue = $0 ? "true" : "false" }))
                    .toggleStyle(.switch).controlSize(.small)
            case .choice(let options):
                Picker(field.title, selection: binding) {
                    Text("—").tag("")
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            case .multiline, .json:
                TextField(field.help ?? (field.kind == .json ? "JSON, e.g. [\"a\", \"b\"]" : ""), text: binding, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: field.kind == .json ? .monospaced : .default))
                    .focused($focusedField, equals: field.name)
            default:
                TextField(field.help ?? "", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($focusedField, equals: field.name)
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        switch run.phase {
        case .running:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Running…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .transition(.opacity)
        case .done:
            if let outcome = run.outcome {
                VStack(alignment: .leading, spacing: 8) {
                    if outcome.report.isFlagged || outcome.aiVerdict?.lowercased().contains("malicious") == true
                        || outcome.aiVerdict?.lowercased().contains("suspicious") == true {
                        InjectionBanner(report: outcome.report, aiVerdict: outcome.aiVerdict)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    HStack {
                        Label(outcome.isError ? "Tool reported an error" : "Result", systemImage: outcome.isError ? "xmark.octagon" : "checkmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(outcome.isError ? .orange : .green)
                        Spacer()
                        Text("\(outcome.durationMs) ms").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Text(highlighted(outcome))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
        default:
            EmptyView()
        }
    }

    /// Suspicious passages get a highlight so the user can see exactly what was flagged.
    private func highlighted(_ outcome: MCPToolRunModel.Outcome) -> AttributedString {
        let text = String(outcome.text.prefix(20_000))
        var s = AttributedString(text)
        for match in outcome.report.matches {
            guard !match.snippet.isEmpty, let r = s.range(of: match.snippet) else { continue }
            s[r].backgroundColor = (match.severity == .malicious ? Color.red : Color.yellow).opacity(0.35)
        }
        return s
    }
}

struct RiskBadge: View {
    let risk: ToolRisk

    var body: some View {
        let tint: Color = risk >= .deletes ? .red : (risk.needsPermission ? .orange : .green)
        Text(risk.title)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.16)))
            .overlay(alignment: .leading) { Circle().fill(tint).frame(width: 5, height: 5).offset(x: -1).opacity(0) }
    }
}

/// Yellow for suspicious, red for likely injection, with the reason.
struct InjectionBanner: View {
    let report: InjectionDetector.Report
    let aiVerdict: String?
    @State private var pulse = false

    var body: some View {
        let severe = report.verdict == .malicious || aiVerdict?.lowercased().contains("malicious") == true
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 18))
                .foregroundStyle(severe ? .red : .orange)
                .symbolEffect(.bounce, value: pulse)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(severe ? "Possible prompt injection" : "Suspicious content")
                    .font(.system(size: 13, weight: .semibold))
                Text(report.isFlagged ? report.summary : "Flagged by the on-device check.")
                    .font(.system(size: 12))
                if let aiVerdict { Text(aiVerdict).font(.system(size: 11)).foregroundStyle(.secondary) }
                Text("This result won't be passed to the AI without your confirmation.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill((severe ? Color.red : Color.yellow).opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder((severe ? Color.red : Color.orange).opacity(0.4), lineWidth: 1))
        .onAppear { pulse = true }
        .accessibilityElement(children: .combine)
    }
}

/// "Allow once / Always allow / Deny" with the exact arguments that will be sent.
struct PermissionSheet: View {
    let tool: MCPClientManager.ToolInfo
    let request: MCPToolRunModel.PermissionRequest
    let onAllowOnce: () -> Void
    let onAlways: () -> Void
    let onDeny: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(request.risk >= .deletes ? .red : .orange)
                    .symbolEffect(.bounce, value: appeared)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow \(tool.name)?").font(.system(size: 14, weight: .semibold))
                    Text("\(tool.serverName) · \(request.risk.title)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                RiskBadge(risk: request.risk)
            }
            Text("These exact arguments will be sent:").font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                Text(prettyArguments)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 110)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            HStack {
                Button("Deny", role: .destructive, action: onDeny).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Always Allow", action: onAlways)
                Button("Allow Once", action: onAllowOnce).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .background(PanelBackground(cornerRadius: 12))
        .overlay(GlassEdge(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permission request for \(tool.name)")
    }

    private var prettyArguments: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? enc.encode(request.arguments)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

struct MCPActivityView: View {
    let model: PanelViewModel

    var body: some View {
        let sections = model.sections
        if sections.isEmpty {
            EmptyStateView(symbol: "list.bullet.rectangle", title: model.query.isEmpty ? "No tool calls yet" : "No matching calls",
                           message: "Every MCP tool call shows up here — allowed, denied or failed. Filter with server:name.")
        } else {
            HStack(spacing: 0) {
                ResultsList(model: model, sections: sections).frame(width: 330)
                Divider()
                if let record = MCPActivity.record(for: model.selectedItem) {
                    AuditDetail(record: record).id(record.id).transition(.opacity)
                }
            }
            .motion(Motion.gentle, value: model.selectedID)
        }
    }
}

private struct AuditDetail: View {
    let record: MCPAuditRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(record.tool)").font(.system(size: 15, weight: .semibold))
                Group {
                    row("Server", record.server)
                    row("When", record.timestamp.formatted(date: .abbreviated, time: .standard))
                    row("Decision", record.decision.capitalized)
                    row("Risk", record.risk)
                    row("Duration", "\(record.durationMs) ms")
                    row("Injection check", record.injection + (record.injectionReason.isEmpty ? "" : " — \(record.injectionReason)"))
                }
                Text("Arguments (secrets masked)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(record.argumentsJSON).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled)
                Text("Result").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(record.resultSummary).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value)
        }
        .font(.system(size: 12))
    }
}
