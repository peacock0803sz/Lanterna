/// The release this binary was stamped with, for on-screen display.
///
/// `StampedVersion.describe` is written by scripts/generate-version.sh at
/// build time. A development build past the tag keeps the full describe
/// string verbatim and derives the short form, so the window always names
/// the binary at hand rather than the last release.
enum AppVersion {
    /// The full describe string, for on-screen display.
    static let full = StampedVersion.describe
    /// The normalized X.Y.Z, for the bundle Info.plist.
    static let short = VersionDescriptor.shortName(from: StampedVersion.describe)
}
