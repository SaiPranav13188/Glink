import os

/// Unified logging categories. Never log user content (keystrokes, clipboard text, AI prompts).
enum Log {
    static let app = Logger(subsystem: "com.saipranav.glink", category: "app")
    static let search = Logger(subsystem: "com.saipranav.glink", category: "search")
    static let system = Logger(subsystem: "com.saipranav.glink", category: "system")
    static let ai = Logger(subsystem: "com.saipranav.glink", category: "ai")
}

