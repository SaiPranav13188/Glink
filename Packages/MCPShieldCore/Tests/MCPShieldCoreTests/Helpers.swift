import Foundation
@testable import MCPShieldCore

/// Fake secrets only. Built at runtime so no key-shaped literal sits in the source.
enum Fake {
    static let github = "ghp_" + String(repeating: "FAKE0", count: 8)           // 40 chars total
    static let aws = "AKIA" + "FAKEFAKEFAKEFAKE"
    static let google = "AIza" + String(repeating: "Fake_", count: 7)            // 35 after the prefix
    static let anthropic = "sk-ant-" + String(repeating: "fakeFAKE", count: 4)
    static let openAI = "sk-proj-" + String(repeating: "FakeFake", count: 4)
    static let githubPAT = "github_pat_11FAKE0000_" + String(repeating: "FAKEfake", count: 7)
    static let slack = "xoxb-000000000000-0000000000000-" + String(repeating: "FAKEfake", count: 3)
    static let plainToken = "f4ke-t0ken-" + String(repeating: "x9", count: 10)  // no known pattern
}

func server(_ name: String = "test", command: String? = nil, args: [String] = [],
            env: [String: String] = [:], url: String? = nil, headers: [String: String] = [:]) -> ServerConfig {
    ServerConfig(name: name, source: "Test", sourcePath: "/tmp/test.json",
                 command: command, args: args, env: env, url: url, headers: headers)
}

func ruleIDs(_ s: ServerConfig) -> Set<String> { Set(ConfigRules.analyze(s).map(\.ruleID)) }

func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "tollgate-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
