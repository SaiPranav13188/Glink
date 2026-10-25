import Foundation

/// Fixtures live in `Fixtures/` under SwiftPM (Bundle.module) and in the test bundle under Xcode.
enum FixtureBundle {
    private final class Token {}

    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle(for: Token.self)
        #endif
    }
}
