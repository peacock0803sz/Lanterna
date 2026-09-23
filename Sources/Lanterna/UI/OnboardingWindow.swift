import AppKit
import SwiftUI

/// Opens one System Settings face.
///
/// A function value rather than a direct call, so the window can be shown a
/// fixed answer about what opened. The production value is below.
typealias SettingsOpener = @MainActor (URL) -> Bool

/// The production opener. Falls back to the Privacy pane itself when the
/// anchor does not resolve: the button still takes the user next to the
/// switch, and the text names the face.
@MainActor
enum SystemSettings {
    /// The Privacy pane, named when no anchor resolves.
    static let privacyPane = URL(string: "x-apple.systempreferences:com.apple.preference.security")!

    static func open(_ url: URL) -> Bool {
        if NSWorkspace.shared.open(url) {
            return true
        }
        return NSWorkspace.shared.open(privacyPane)
    }
}

/// One missing permission, as the guide shows it.
struct MissingPermission: Identifiable, Equatable {
    /// Accessibility or Input Monitoring. Never anything else.
    enum Kind: Equatable {
        case accessibility
        case inputMonitoring
    }

    var id: Kind {
        kind
    }

    let kind: Kind
    /// The name as System Settings shows the face.
    let name: String
    /// The face this button opens.
    let settingsURL: URL
}

/// Builds the guide rows for exactly the permissions still missing.
extension MissingPermission {
    /// The faces as System Settings names them, in the order the guide shows.
    /// The anchors below opened the right faces on macOS 27.0 (26A428); the
    /// names stay worded so the guide still reads if an anchor ever lands on
    /// the Privacy pane instead (see the spike record in research.md).
    static func list(for state: PermissionState) -> [MissingPermission] {
        var missing: [MissingPermission] = []
        if !state.accessibilityGranted {
            missing.append(MissingPermission(
                kind: .accessibility,
                name: "Accessibility",
                settingsURL: URL(
                    string: "x-apple.systempreferences:com.apple.preference.security"
                        + "?Privacy_Accessibility"
                )!
            ))
        }
        if !state.inputMonitoringGranted {
            missing.append(MissingPermission(
                kind: .inputMonitoring,
                name: "Input Monitoring",
                settingsURL: URL(
                    string: "x-apple.systempreferences:com.apple.preference.security"
                        + "?Privacy_ListenEvent"
                )!
            ))
        }
        return missing
    }
}

/// The launch-time permission guide.
///
/// A regular window rather than the reused switcher panel: the panel is
/// non-activating by design, while this guide holds buttons the user clicks.
/// It owns no keyboard monitoring of any kind.
@MainActor
final class OnboardingWindow: NSWindow {
    /// Builds the window for exactly the permissions still missing. Opening
    /// with nothing missing shows the all-clear state rather than an empty
    /// guide, so the menu entry never opens a dead window.
    convenience init(missing: [MissingPermission], opener: @escaping SettingsOpener) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Lanterna needs permissions"
        contentView = NSHostingView(rootView: OnboardingView(missing: missing, opener: opener))
        center()
    }
}

/// The guide contents.
///
/// Names two permissions and only those two. Screen Recording appears nowhere
/// here: asking for it would contradict what this app promises.
struct OnboardingView: View {
    let missing: [MissingPermission]
    let opener: SettingsOpener

    /// What is actually broken decides the headline. Without Accessibility no
    /// list can be built; without only Input Monitoring the list still
    /// appears but the panel stops closing on Command release.
    var headline: String {
        if missing.isEmpty {
            "Lanterna has the permissions it needs"
        } else if missing.contains(where: { $0.kind == .accessibility }) {
            "Lanterna cannot list windows yet"
        } else {
            "Lanterna cannot notice Command being released"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                }
                Text(headline)
                    .font(.headline)
            }
            if missing.isEmpty {
                Text("Both permissions are granted. Restarting changes nothing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Group {
                    Text("Grant the missing permissions, then restart Lanterna.")
                    Text("A grant takes effect on the next launch, not this one.")
                }
                .font(.body)
                .foregroundStyle(.secondary)
                ForEach(missing) { permission in
                    HStack {
                        Text(permission.name)
                        Spacer()
                        Button("Open Settings") {
                            _ = opener(permission.settingsURL)
                        }
                    }
                }
                Text("System Settings → Privacy & Security → Accessibility, Input Monitoring")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
