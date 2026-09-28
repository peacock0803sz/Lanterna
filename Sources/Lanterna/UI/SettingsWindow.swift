import AppKit
import SwiftUI

/// The settings window.
///
/// A regular window like the onboarding and version windows: it holds
/// controls the user clicks, so the non-activating switcher panel cannot
/// host them. The content is a tab view; each tab owns one concern and
/// edits the same values, so a change anywhere applies everywhere at
/// once through the single change handler.
@MainActor
final class SettingsWindow: NSWindow {
    /// Builds the window showing the given values. Changes flow back
    /// through `onChange` as they happen; saving and confirmation live
    /// with the caller, not here.
    convenience init(
        values: SettingsValues,
        version: DisplayedVersion,
        permissionState: PermissionState,
        opener: @escaping SettingsOpener,
        appearanceMode: AppearanceMode = .system,
        checkDisplay: UpdateCheckDisplay = UpdateCheckDisplay(),
        onCheckNow: @escaping () -> Void = {},
        onChange: @escaping (SettingsValues) -> Void
    ) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Lanterna Settings"
        appearance = appearanceMode.nsAppearance
        contentView = NSHostingView(rootView: SettingsView(
            values: values,
            version: version,
            permissionState: permissionState,
            opener: opener,
            checkDisplay: checkDisplay,
            onCheckNow: onCheckNow,
            onChange: onChange
        ))
        center()
    }
}

/// The tabbed settings contents.
///
/// One state for all tabs: each picker edits the shared values, and any
/// edit reports the whole snapshot. Reporting the whole thing keeps the
/// caller free of per-tab plumbing; it always sees complete settings.
struct SettingsView: View {
    @State private var values: SettingsValues
    let version: DisplayedVersion
    let permissionState: PermissionState
    let opener: SettingsOpener
    @ObservedObject var checkDisplay: UpdateCheckDisplay
    let onCheckNow: () -> Void
    let onChange: (SettingsValues) -> Void

    init(
        values: SettingsValues,
        version: DisplayedVersion,
        permissionState: PermissionState,
        opener: @escaping SettingsOpener,
        checkDisplay: UpdateCheckDisplay = UpdateCheckDisplay(),
        onCheckNow: @escaping () -> Void = {},
        onChange: @escaping (SettingsValues) -> Void
    ) {
        self.values = values
        self.version = version
        self.permissionState = permissionState
        self.opener = opener
        self.checkDisplay = checkDisplay
        self.onCheckNow = onCheckNow
        self.onChange = onChange
    }

    var body: some View {
        TabView {
            SettingsGeneralView(
                values: $values,
                version: version,
                missing: MissingPermission.list(for: permissionState),
                opener: opener,
                checkResultText: checkDisplay.resultText,
                isChecking: checkDisplay.isChecking,
                onCheckNow: onCheckNow
            )
            .tabItem { Text("General") }
            SettingsAppearanceView(values: $values)
                .tabItem { Text("Appearance") }
            SettingsFilterView(values: $values)
                .tabItem { Text("Filter") }
        }
        .onChange(of: values) { _, newValues in
            onChange(newValues)
        }
        .frame(width: 480, height: 360)
    }
}
