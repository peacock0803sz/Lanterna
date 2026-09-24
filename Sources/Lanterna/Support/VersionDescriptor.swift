/// Interprets the stamped `git describe` string for on-screen display.
///
/// The stamp itself is written by scripts/generate-version.sh at build time;
/// this only reads it, so the rules stay testable without git or a build.
enum VersionDescriptor {
    /// The X.Y.Z for the bundle and for comparison: the leading `v` dropped
    /// and anything from the first `-` on discarded. A string with no tag
    /// shape (a bare hash from a tagless checkout, or anything else that is
    /// not `vX.Y.Z` up front) names no release, so it falls back.
    static func shortName(from describe: String) -> String {
        guard describe.hasPrefix("v") else {
            return "0.0.0"
        }
        let core = describe.dropFirst().prefix(while: { $0 != "-" })
        let parts = core.split(separator: ".")
        guard parts.count == 3 else {
            return "0.0.0"
        }
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isNumber }) else {
                return "0.0.0"
            }
        }
        return String(core)
    }
}
