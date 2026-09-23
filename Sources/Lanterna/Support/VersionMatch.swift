import Foundation

/// Whether the on-screen version and the bundle version name the same release.
///
/// The rule is one equality: the full describe string minus its leading `v`
/// equals the short version. A commit past the tag or a dirty tree leaves a
/// suffix behind, and a string without the `v` never had the tag's shape, so
/// neither matches.
enum VersionMatch {
    static func matches(full: String, short: String) -> Bool {
        guard !short.isEmpty, full.hasPrefix("v") else {
            return false
        }
        return full.dropFirst() == short[...]
    }
}
