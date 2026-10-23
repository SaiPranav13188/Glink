import Foundation

public enum Scoring {
    public static let weights: [Category: Double] = [.config: 0.30, .secrets: 0.35, .tools: 0.25, .privacy: 0.10]

    public static func score(_ findings: [Finding]) -> (total: Int, perCategory: [String: Int]) {
        var per: [Category: Int] = [:]
        for c in Category.allCases { per[c] = 100 }
        for f in findings { per[f.category] = max(0, (per[f.category] ?? 100) - f.severity.penalty) }
        var total = Int((Category.allCases.reduce(0.0) { $0 + Double(per[$1] ?? 100) * (weights[$1] ?? 0) }).rounded())
        // Caps keep one serious problem from being averaged away into a green score.
        if findings.contains(where: { $0.severity == .critical }) { total = min(total, 59) }
        if findings.contains(where: { $0.severity == .high }) { total = min(total, 84) }
        return (total, Dictionary(uniqueKeysWithValues: per.map { ($0.key.rawValue, $0.value) }))
    }

    public static func grade(_ s: Int) -> String { s >= 85 ? "Good" : s >= 60 ? "Needs work" : "At risk" }
}

/// Runs every v1 check on one server and scores it.
public enum Scanner {
    public static func scan(_ s: ServerConfig) -> ScanResult {
        // Last line of defence: no rule may put a full secret into a finding.
        let sensitive = Report.sensitiveValues(in: [s])
        func clean(_ text: String) -> String {
            sensitive.reduce(Secrets.redactMatches(in: text)) { $0.replacingOccurrences(of: $1, with: Secrets.redact($1)) }
        }
        let findings = (ConfigRules.analyze(s) + Secrets.scan(s))
            .map { f in
                var f = f
                f.detail = clean(f.detail)
                f.evidence = f.evidence.map(clean)
                return f
            }
            .sorted { ($0.severity.rank, $0.ruleID, $0.target) < ($1.severity.rank, $1.ruleID, $1.target) }
        let (total, cats) = Scoring.score(findings)
        return ScanResult(server: s, findings: findings, score: total, categoryScores: cats)
    }

    public static func scan(_ servers: [ServerConfig]) -> [ScanResult] { servers.map(scan) }
}
