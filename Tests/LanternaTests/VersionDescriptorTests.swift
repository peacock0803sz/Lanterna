@testable import Lanterna
import Testing

/// Deriving display values from the stamped `git describe` string.
///
/// A clean tag names its own short version; a describe past the tag or with
/// a dirty tree keeps the tag's X.Y.Z for the short form while the full
/// string stays verbatim. A checkout with no tag to name (bare hash) has no
/// short version to derive, so it falls back.
struct VersionDescriptorTests {
    @Test(arguments: [
        ("v0.3.0", "0.3.0"),
        ("v1.2.3", "1.2.3"),
        ("v0.3.0-12-ga72a891", "0.3.0"),
        ("v0.3.0-12-ga72a891-dirty", "0.3.0"),
        ("v1.2.3-dirty", "1.2.3"),
    ])
    func shortNameKeepsTheTaggedRelease(describe: String, short: String) {
        #expect(VersionDescriptor.shortName(from: describe) == short)
    }

    @Test(arguments: [
        "a72a891",
        "a72a891-dirty",
        "",
        "0.3.0",
        "v0.3",
    ])
    func shortNameFallsBackWithoutATagShape(describe: String) {
        #expect(VersionDescriptor.shortName(from: describe) == "0.0.0")
    }
}
