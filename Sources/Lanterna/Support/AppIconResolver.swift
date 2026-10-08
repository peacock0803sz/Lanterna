import AppKit
import UniformTypeIdentifiers

/// Looks up icons of applications installed on this machine.
///
/// Using real icons keeps the mock faithful to the final appearance. Entries
/// whose application is absent fall back to the generic application icon, which
/// keeps the icon slot visibly filled and satisfies the non-optional icon type.
@MainActor
enum AppIconResolver {

  // MARK: Internal

  /// Generic application icon, resolved once so unresolved rows share one
  /// image instead of allocating a copy per row.
  static let placeholder: NSImage = NSWorkspace.shared.icon(for: .applicationBundle)

  /// How many icons are held. Watched from the diagnostics, not capped:
  /// one entry per application bounds it in practice.
  static var cachedCount: Int {
    iconsByBundleIdentifier.count
  }

  /// Several windows of one application are the normal case, so each bundle
  /// identifier is looked up in the workspace at most once.
  static func icon(forBundleIdentifier bundleIdentifier: String?) -> NSImage {
    guard let bundleIdentifier else {
      return placeholder
    }
    if let cached = iconsByBundleIdentifier[bundleIdentifier] {
      return cached
    }

    let icon: NSImage =
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
        NSWorkspace.shared.icon(forFile: url.path)
      } else {
        placeholder
      }
    iconsByBundleIdentifier[bundleIdentifier] = icon
    return icon
  }

  // MARK: Private

  private static var iconsByBundleIdentifier = [String: NSImage]()

}
