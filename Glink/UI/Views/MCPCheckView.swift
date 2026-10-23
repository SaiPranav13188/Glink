import GlinkCore
import MCPShieldCore
import SwiftUI

/// MCP Config Check: Tollgate's per-server scores, grouped by grade, with every finding's fix.
struct MCPCheckView: View {
    let model: PanelViewModel
    private var mcp: MCPCheckModel { model.mcp }

    var body: some View {
        VStack(spacing: 0) {
            summary
                .padding(.horizontal, 18)
                .frame(height: 104)
            Divider()
            content
        }
    }

    // MARK: Summary header with animated score gauge

    private var summary: some View {
        HStack(spacing: 18) {
            ScoreGauge(progress: mcp.gaugeProgress, scanning: mcp.isScanning || mcp.report == nil,
                       hasServers: !(mcp.report?.results.isEmpty ?? true))
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                if mcp.isScanning || mcp.report == nil {
                    Text("Scanning MCP configs…").font(.system(size: 15, weight: .semibold))
                    Text("Claude, Cursor, VS Code, Windsurf, Zed, Gemini and more · read-only")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else if let report = mcp.report {
                    Text(headline(for: report)).font(.system(size: 15, weight: .semibold))
                    Text("\(report.results.count) server\(report.results.count == 1 ? "" : "s") in \(report.files.count) config file\(report.files.count == 1 ? "" : "s") · rules by Tollgate")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(Severity.allCases, id: \.self) { sev in
                            let count = report.count(sev)
                            if count > 0 { SeverityBadge(severity: sev, text: "\(count) \(sev.rawValue.capitalized)") }
                        }
                    }
                }
            }
            .transition(.opacity)
            Spacer()
        }
        .motion(Motion.smooth, value: mcp.isScanning)
    }

    private func headline(for report: MCPReport) -> String {
        if report.results.isEmpty { return "No MCP servers found" }
        let atRisk = report.results.filter { $0.grade == "At risk" }.count
        switch report.grade {
        case "Good": return "Looking good"
        case "Needs work": return "Some settings need work"
        default: return "\(atRisk) server\(atRisk == 1 ? " is" : "s are") at risk"
        }
    }

    // MARK: Servers + detail

    @ViewBuilder
    private var content: some View {
        if mcp.isScanning || mcp.report == nil {
            SkeletonList(rows: 5)
        } else if let report = mcp.report {
            if report.results.isEmpty {
                EmptyStateView(symbol: "doc.questionmark", title: "No MCP servers configured",
                               message: report.files.isEmpty
                                   ? "Glink checked Claude Desktop, Claude Code, Cursor, VS Code, Windsurf, Zed, Gemini CLI and Continue."
                                   : "Glink read \(report.files.count) config file\(report.files.count == 1 ? "" : "s"), but none define MCP servers yet.")
            } else if model.sections.isEmpty {
                EmptyStateView(symbol: "line.3.horizontal.decrease.circle", title: "No matching servers",
                               message: "Try a server name, a client, or a rule like CFG-001.")
            } else {
                HStack(spacing: 0) {
                    ResultsList(model: model, sections: model.sections)
                        .frame(width: 300)
                    Divider()
                    if let result = mcp.result(for: model.selectedItem) {
                        ServerDetail(result: result)
                            .id(result.id)
                            .transition(.opacity)
                    }
                }
                .motion(Motion.gentle, value: model.selectedID)
            }
        }
    }
}

private struct ScoreGauge: View {
    let progress: Double
    let scanning: Bool
    let hasServers: Bool
    @State private var spin = false

    private var score: Int { Int((progress * 100).rounded()) }
    private var color: Color { score >= 85 ? .green : score >= 60 ? .orange : .red }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 7)
            if scanning {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
                    }
            } else {
                Circle()
                    .trim(from: 0, to: hasServers ? progress : 0)
                    .stroke(AngularGradient(colors: [color.opacity(0.7), color], center: .center),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -1) {
                    Text(hasServers ? "\(score)" : "–")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: progress))
                    if hasServers {
                        Text("lowest").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        // The ring fills and the score counts up with a slow, settling spring.
        .animation(Motion.isOff ? nil : .spring(response: 0.9, dampingFraction: 0.85), value: progress)
        // To assistive tech it's a gauge: a progress indicator with a spoken value.
        .accessibilityRepresentation {
            ProgressView(value: scanning ? 0 : progress)
                .accessibilityLabel(scanning ? "Scanning MCP configs" : "Lowest server score")
                .accessibilityValue(scanning ? "In progress" : (hasServers ? "\(score) out of 100" : "No servers"))
        }
    }
}

private struct SeverityBadge: View {
    let severity: Severity
    let text: String

    var body: some View {
        let style = MCPCheckModel.severityStyle(severity)
        // Color lives on the icon and the tint; the text stays primary so it reads at full contrast.
        HStack(spacing: 4) {
            Image(systemName: style.symbol).accessibilityHidden(true).font(.system(size: 10)).foregroundStyle(style.tint.color)
            Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(style.tint.color.opacity(0.16)))
    }
}

private struct ServerDetail: View {
    let result: MCPServerResult
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.raw.name).font(.system(size: 16, weight: .semibold))
                        Text("\(result.raw.source) · \((result.raw.configPath as NSString).abbreviatingWithTildeInPath)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Spacer()
                    let style = MCPCheckModel.gradeStyle(result.score)
                    Label("\(result.score) · \(result.grade)", systemImage: style.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(style.tint.color.opacity(0.12)))
                }
                if !result.displayCommand.isEmpty {
                    Text(result.displayCommand)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                }
                if result.findings.isEmpty {
                    Label("No issues found for this server.", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: appeared)
                }
                ForEach(Array(result.findings.enumerated()), id: \.element.id) { index, finding in
                    FindingCard(finding: finding)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 6)
                        .animation(Motion.resolved(Motion.smooth)?.delay(Double(min(index, 6)) * Motion.staggerStep * 2), value: appeared)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { appeared = true }
    }
}

private struct FindingCard: View {
    let finding: Finding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SeverityBadge(severity: finding.severity, text: finding.severity.rawValue.capitalized)
                Text(finding.ruleID).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(finding.title).font(.system(size: 13, weight: .semibold))
            if !finding.detail.isEmpty {
                Text(finding.detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let evidence = finding.evidence, !evidence.isEmpty {
                Text(evidence).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
            }
            if !finding.fix.isEmpty {
                Label {
                    Text(finding.fix).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                } icon: {
                    Image(systemName: "wrench.and.screwdriver").accessibilityHidden(true).foregroundStyle(.green)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.green.opacity(0.08)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.035)))
    }
}
