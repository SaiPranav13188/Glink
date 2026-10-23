import Foundation

/// v1 config rules. These are heuristics: each one has tests and a measured false-alarm rate (EvalSet/).
public enum ConfigRules {
    public static let allRuleIDs = ["CFG-001", "CFG-002", "CFG-003", "CFG-004", "CFG-005", "CFG-006"]

    public static func analyze(_ s: ServerConfig) -> [Finding] {
        var out: [Finding] = []
        out += secretInConfig(s)
        out += unpinnedPackage(s)
        out += insecureTransport(s)
        out += shellLaunch(s)
        out += broadFolderAccess(s)
        out += writableExecutable(s)
        return out
    }

    // MARK: CFG-001: secrets written into the config (env, headers, args, URLs)

    // v1 baseline only read env and matched pieces of words; see EvalSet/results-*.md.
    static let secretWords: Set<String> = ["key", "token", "secret", "password", "passwd", "pwd", "apikey",
                                           "auth", "authorization", "credential", "credentials", "cookie"]
    /// `SSH_KEY_PATH`, `--api-key-env`, `--token-limit`, `ACCESS_KEY_ID` name a secret's location or size, not the secret.
    static let notSecretWords: Set<String> = ["path", "file", "dir", "field", "name", "id", "env", "var",
                                              "limit", "max", "count", "size", "type", "url", "endpoint", "host"]

    static func isSecretName(_ name: String) -> Bool {
        let w = ToolRules.words(name)
        return w.contains(where: secretWords.contains) && !w.contains(where: notSecretWords.contains)
    }

    /// A value that is the secret itself, not a reference to one (`${TOKEN}`), a path, an env var name or a placeholder.
    static func isLiteralSecret(_ raw: String) -> Bool {
        var v = raw.trimmingCharacters(in: .whitespaces)
        for scheme in ["bearer ", "basic ", "token "] where v.lowercased().hasPrefix(scheme) { v = String(v.dropFirst(scheme.count)) }
        guard v.count >= 12, !v.contains("://"), !Secrets.isPlaceholder(v) else { return false }
        if v.contains("${") || v.contains("$(") || v.hasPrefix("$") || v.contains("{{") { return false }
        if v.hasPrefix("/") || v.hasPrefix("~/") || v.hasPrefix("./") { return false }
        if v.range(of: #"^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$"#, options: .regularExpression) != nil { return false }
        return true
    }

    /// The password in `scheme://user:password@host`, if it is written out.
    static func connectionPassword(_ value: String) -> String? {
        guard let r = value.range(of: #"[A-Za-z][A-Za-z0-9+.\-]*://[^:/@\s]+:([^@\s]+)@"#, options: .regularExpression) else { return nil }
        let match = value[r].dropLast()                          // drop the "@"
        guard let colon = match.lastIndex(of: ":") else { return nil }
        let pw = String(match[match.index(after: colon)...])
        if pw.count < 3 || pw.contains("${") || pw.hasPrefix("$") || Secrets.isPlaceholder(pw) { return nil }
        return pw
    }

    static func secretInConfig(_ s: ServerConfig) -> [Finding] {
        var out: [Finding] = []
        var seen = Set<String>()
        func add(_ target: String, _ value: String, _ detail: String) {
            guard seen.insert(target).inserted else { return }
            out.append(Finding(ruleID: "CFG-001", title: "Secret stored in plain text in config",
                severity: .high, category: .secrets, target: target, detail: detail,
                fix: "Remove it from the file and load it from the Keychain or a secrets manager. Rotate it, since the file may have been shared or backed up.",
                evidence: Secrets.redact(value)))
        }
        let plain = "Anyone who can read this file, a backup of it, or a screenshot of it gets the secret."
        let inConnection = "The connection string includes its password. " + plain
        let inURL = "Secrets in a URL also end up in server logs and browser history. " + plain

        for (key, value) in s.env.sorted(by: { $0.key < $1.key }) {
            let target = "\(s.name).env.\(key)"
            if isSecretName(key) && isLiteralSecret(value) { add(target, value, plain) }
            if let pw = connectionPassword(value) { add(target, pw, inConnection) }
        }
        let authHeaders: Set<String> = ["authorization", "proxy-authorization", "cookie"]
        for (key, value) in s.headers.sorted(by: { $0.key < $1.key })
        where (authHeaders.contains(key.lowercased()) || isSecretName(key)) && isLiteralSecret(value) {
            add("\(s.name).headers.\(key)", value, plain)
        }
        for (i, arg) in s.args.enumerated() {
            let target = "\(s.name).args[\(i)]"
            if let pw = connectionPassword(arg) { add(target, pw, inConnection); continue }
            // `--api-key=x` and docker's `-e NAME=x`
            if let eq = arg.firstIndex(of: "=") {
                let name = arg[..<eq].drop(while: { $0 == "-" })
                if name.range(of: #"^[A-Za-z_][A-Za-z0-9_\-]*$"#, options: .regularExpression) != nil,
                   isSecretName(String(name)), isLiteralSecret(String(arg[arg.index(after: eq)...])) {
                    add(target, String(arg[arg.index(after: eq)...]), plain)
                }
            } else if arg.hasPrefix("-"), isSecretName(arg), i + 1 < s.args.count,
                      !s.args[i + 1].hasPrefix("-"), isLiteralSecret(s.args[i + 1]) {
                add("\(s.name).args[\(i + 1)]", s.args[i + 1], plain)
            }
        }
        if let url = s.url {
            if let pw = connectionPassword(url) { add("\(s.name).url", pw, inURL) }
            for item in URLComponents(string: url)?.queryItems ?? []
            where isSecretName(item.name) && isLiteralSecret(item.value ?? "") {
                add("\(s.name).url", item.value ?? "", inURL)
            }
        }
        return out
    }

    // MARK: CFG-002: unpinned package

    // v1 baseline treated any "@" as pinned and missed Python-style pins; see EvalSet/results-*.md.
    enum Ecosystem { case npm, python }

    static func unpinnedPackage(_ s: ServerConfig) -> [Finding] {
        guard let cmd = s.command else { return [] }
        let tokens = cmd.split(separator: " ").map(String.init) + s.args
        guard let (eco, spec) = packageSpec(tokens), !isPinned(spec, eco) else { return [] }
        return [Finding(ruleID: "CFG-002", title: "Package version is not pinned",
            severity: .medium, category: .config, target: s.name,
            detail: "Each launch may download new code.",
            fix: eco == .npm ? "Pin an exact version, for example package@1.2.3."
                             : "Pin an exact version, for example package==1.2.3.",
            evidence: spec.isEmpty ? nil : spec)]
    }

    /// The package a launcher will download, e.g. `["npx", "-y", "pkg@1.0.0"]` -> (.npm, "pkg@1.0.0").
    static func packageSpec(_ tokens: [String]) -> (Ecosystem, String)? {
        guard let first = tokens.first else { return nil }
        var rest = Array(tokens.dropFirst())
        switch (first as NSString).lastPathComponent {
        case "npx", "bunx":
            return (.npm, firstPositional(rest, valueFlags: ["--package", "-p", "--call", "-c"], specFlags: ["--package", "-p"]))
        case "pnpm", "yarn":
            guard rest.first == "dlx" else { return nil }
            return (.npm, firstPositional(Array(rest.dropFirst()), valueFlags: ["--package", "-p"], specFlags: ["--package", "-p"]))
        case "uvx":
            return (.python, firstPositional(rest, valueFlags: ["--from", "--python", "-p", "--with", "--index-url", "--extra-index-url"],
                                             specFlags: ["--from"]))
        case "pipx":
            guard rest.first == "run" else { return nil }
            rest.removeFirst()
            return (.python, firstPositional(rest, valueFlags: ["--spec", "--python", "--index-url"], specFlags: ["--spec"]))
        case let sh where shells.contains(sh):
            // `bash -c "npx -y pkg"`: look inside the command string.
            guard let i = rest.firstIndex(where: { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("c") }),
                  i + 1 < rest.count else { return nil }
            let inner = rest[(i + 1)...].joined(separator: " ")
                .split(whereSeparator: { " ;&|'\"".contains($0) }).map(String.init)
            guard let start = inner.firstIndex(where: { ["npx", "bunx", "uvx", "pipx"].contains(($0 as NSString).lastPathComponent) })
            else { return nil }
            return packageSpec(Array(inner[start...]))
        default:
            return nil
        }
    }

    /// A spec flag's value (`--from x`, `--package=x`) wins; otherwise the first argument that is not a flag or a flag's value.
    private static func firstPositional(_ args: [String], valueFlags: Set<String>, specFlags: Set<String>) -> String {
        var i = 0, positional: String?
        while i < args.count {
            let a = args[i]
            if let eq = a.firstIndex(of: "="), a.hasPrefix("-") {
                if specFlags.contains(String(a[..<eq])) { return String(a[a.index(after: eq)...]) }
            } else if valueFlags.contains(a) {
                if specFlags.contains(a), i + 1 < args.count { return args[i + 1] }
                i += 1
            } else if !a.hasPrefix("-"), positional == nil {
                positional = a
            }
            i += 1
        }
        return positional ?? ""
    }

    static func isPinned(_ spec: String, _ eco: Ecosystem) -> Bool {
        func matches(_ s: Substring, _ re: String) -> Bool { s.range(of: re, options: .regularExpression) != nil }
        switch eco {
        case .npm:
            let body = spec.hasPrefix("@") ? spec.dropFirst() : Substring(spec)   // skip a leading scope "@"
            guard let at = body.lastIndex(of: "@") else { return false }
            return matches(body[body.index(after: at)...], #"^v?\d+\.\d+\.\d+([-+][0-9A-Za-z.\-]+)?$"#)
        case .python:
            if let r = spec.range(of: "===") ?? spec.range(of: "==") {
                return matches(spec[r.upperBound...], #"^\s*\d[0-9A-Za-z.\-+]*$"#)
            }
            if let at = spec.lastIndex(of: "@"), !spec.contains("://") {
                return matches(spec[spec.index(after: at)...], #"^v?\d+(\.\d+)*([0-9A-Za-z.\-+]*)$"#)
            }
            return false
        }
    }

    // MARK: CFG-003: remote server over plain HTTP

    /// Local bridges that connect to a remote server given as an argument.
    static let proxies = ["mcp-remote", "supergateway", "mcp-proxy"]

    static func insecureTransport(_ s: ServerConfig) -> [Finding] {
        var urls: [(target: String, url: String)] = []
        if let url = s.url { urls.append(("\(s.name).url", url)) }
        let launch = ([s.command ?? ""] + s.args).joined(separator: " ").lowercased()
        if proxies.contains(where: launch.contains) {
            for (i, arg) in s.args.enumerated() {
                let value = arg.hasPrefix("-") ? arg.split(separator: "=", maxSplits: 1).dropFirst().first.map(String.init) ?? "" : arg
                urls.append(("\(s.name).args[\(i)]", value))
            }
        }
        return urls.filter { $0.url.lowercased().hasPrefix("http://") && !isLocalhost($0.url) }.map { target, url in
            Finding(ruleID: "CFG-003", title: "Remote server uses plain HTTP",
                severity: .high, category: .config, target: target,
                detail: "Traffic, including any tokens, can be read or changed by anyone on the network path.",
                fix: "Use an https:// URL.",
                evidence: Secrets.redactMatches(in: hostOnly(url)))
        }
    }

    static func isLocalhost(_ url: String) -> Bool {
        guard let host = URLComponents(string: url)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]" || host.hasSuffix(".localhost")
    }

    private static func hostOnly(_ url: String) -> String {
        guard let c = URLComponents(string: url), let host = c.host else { return "http://..." }
        return "http://\(host)\(c.port.map { ":\($0)" } ?? "")/..."
    }

    // MARK: CFG-004: launched through a shell

    static let shells: Set<String> = ["sh", "bash", "zsh", "fish", "dash", "ksh", "csh", "tcsh"]

    static func shellLaunch(_ s: ServerConfig) -> [Finding] {
        guard let cmd = s.command else { return [] }
        // Some configs put the whole command line in "command".
        let tokens = cmd.split(separator: " ").map(String.init) + s.args
        guard let first = tokens.first, shells.contains((first as NSString).lastPathComponent) else { return [] }
        let hasDashC = tokens.dropFirst().contains { t in
            t.hasPrefix("-") && !t.hasPrefix("--") && t.dropFirst().contains("c")   // -c, -lc, -ic
        }
        guard hasDashC else { return [] }
        return [Finding(ruleID: "CFG-004", title: "Server is launched through a shell",
            severity: .medium, category: .config, target: s.name,
            detail: "A shell command string can expand variables, chain commands and hide what really runs.",
            fix: "Put the server executable in \"command\" and its arguments in \"args\".",
            evidence: (first as NSString).lastPathComponent + " -c ...")]
    }

    // MARK: CFG-005: folder access that is too wide

    static func broadFolderAccess(_ s: ServerConfig) -> [Finding] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let broad: Set<String> = ["/", "~", "~/", "$HOME", "${HOME}", "/Users", "/Users/", home, home + "/"]
        let haystack = ([s.name, s.command ?? ""] + s.args).joined(separator: " ").lowercased()
        // Any container that mounts a broad folder can read it, whatever the server does.
        let hits = (haystack.contains("filesystem") ? s.args : []) + dockerMountSources(s)
        return hits.filter { broad.contains($0) }.map { path in
            Finding(ruleID: "CFG-005", title: "Folder access is too wide",
                severity: .high, category: .config, target: s.name,
                detail: "The server can read (and possibly change) every file under \(path), including keys, documents and other apps' data.",
                fix: "Give access to one specific project folder instead.",
                evidence: path)
        }
    }

    /// Host folders in `docker run -v SRC:DST` and `--mount type=bind,src=SRC,...`.
    static func dockerMountSources(_ s: ServerConfig) -> [String] {
        guard let cmd = s.command, ["docker", "podman"].contains((cmd as NSString).lastPathComponent) else { return [] }
        var out: [String] = []
        for (i, arg) in s.args.enumerated() {
            let (flag, inline) = arg.hasPrefix("--") && arg.contains("=")
                ? (String(arg.prefix(while: { $0 != "=" })), String(arg.drop(while: { $0 != "=" }).dropFirst()))
                : (arg, nil)
            guard ["-v", "--volume", "--mount"].contains(flag) else { continue }
            guard let value = inline ?? (i + 1 < s.args.count ? s.args[i + 1] : nil) else { continue }
            if flag == "--mount" {
                for part in value.split(separator: ",") where part.hasPrefix("src=") || part.hasPrefix("source=") {
                    out.append(String(part.drop(while: { $0 != "=" }).dropFirst()))
                }
            } else {
                out.append(String(value.prefix(while: { $0 != ":" })))
            }
        }
        return out
    }

    // MARK: CFG-006: executable that others can change

    static let trustedPrefixes = ["/usr/bin/", "/bin/", "/usr/sbin/", "/sbin/", "/System/", "/usr/libexec/"]
    static let interpreters: Set<String> = ["node", "python", "python3", "deno", "bun", "ruby", "perl", "php"]

    static func writableExecutable(_ s: ServerConfig) -> [Finding] {
        guard let cmd = s.command else { return [] }
        var paths: [String] = []
        if cmd.contains("/") { paths.append(cmd) }
        // `node /path/server.js` runs the script, so check the script too.
        if interpreters.contains((cmd as NSString).lastPathComponent),
           let script = s.args.first(where: { !$0.hasPrefix("-") }), script.contains("/") {
            paths.append(script)
        }
        var out: [Finding] = []
        for raw in paths {
            let path = (raw as NSString).expandingTildeInPath
            guard path.hasPrefix("/"), !trustedPrefixes.contains(where: path.hasPrefix) else { continue }
            let parent = (path as NSString).deletingLastPathComponent
            for candidate in [path, parent] where isWritableByOthers(candidate) {
                out.append(Finding(ruleID: "CFG-006", title: "Server runs from a path others can change",
                    severity: .low, category: .config, target: s.name,
                    detail: "\(candidate == path ? "The file" : "Its folder") is writable by other users, so someone else could swap the code that runs.",
                    fix: "Move it to a folder only you can change, or run chmod go-w on it.",
                    evidence: candidate))
                break
            }
        }
        return out
    }

    static func isWritableByOthers(_ path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let perms = attrs[.posixPermissions] as? NSNumber else { return false }
        return perms.intValue & 0o022 != 0     // group-writable or world-writable
    }
}
