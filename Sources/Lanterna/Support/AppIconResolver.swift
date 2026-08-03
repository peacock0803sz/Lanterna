import AppKit
import UniformTypeIdentifiers

/// Looks up icons of applications installed on this machine.
///
/// Using real icons keeps the mock faithful to the final appearance. Entries
/// whose application is absent fall back to the generic application icon so
/// every row keeps its icon slot and the columns stay aligned.
@MainActor
enum AppIconResolver {
    static func icon(forBundleIdentifier bundleIdentifier: String?) -> NSImage {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            return placeholder
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static var placeholder: NSImage {
        NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
