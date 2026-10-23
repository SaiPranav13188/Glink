import AppKit

// Entry point. Glink is a menu bar app (LSUIElement), so it runs an AppKit lifecycle
// and builds its panel, settings and onboarding windows itself. Top-level code runs on
// the main thread, which AppKit and the main actor both require.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
