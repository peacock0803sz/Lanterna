import SwiftUI

/// What the General tab shows about the last manual check.
///
/// Owned by the settings window; the settings view only observes it.
/// The text starts unset and is replaced on every check, never carried
/// across launches.
@MainActor
final class UpdateCheckDisplay: ObservableObject {
    @Published var resultText: String?
    @Published var isChecking = false
}

/// The General tab: launch behavior, update checks, version, and permission state.
///
/// The permission part stays display-only, like the guide it replaces:
/// the state is the launch-time snapshot, and a grant given mid-run
/// waits for the next launch. Future general options (update checks)
/// join this tab.
struct SettingsGeneralView: View {
    @Binding var values: SettingsValues
    let version: DisplayedVersion
    let missing: [MissingPermission]
    let opener: SettingsOpener
    var checkResultText: String?
    var isChecking = false
    var onCheckNow: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 40, height: 40)
                }
                Text("Lanterna \(version.full)")
                    .font(.headline)
                    .textSelection(.enabled)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Launch at login", isOn: $values.launchAtLogin)
                Text("Start Lanterna automatically when you log in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Updates")
                    .font(.headline)
                Toggle("Check for updates", isOn: $values.updateCheckEnabled)
                    .disabled(isChecking)
                Text("Ask whether a newer release is published.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("Channel", selection: $values.updateChannel) {
                    Text("Stable").tag(UpdateChannel.stable)
                    Text("Beta").tag(UpdateChannel.beta)
                }
                .disabled(isChecking)
                Text("Stable covers full releases only. Beta also covers prereleases.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Check now", action: onCheckNow)
                        .disabled(!values.updateCheckEnabled || isChecking)
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text(checkResultText ?? "Not checked yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Open version history") {
                    _ = opener(UpdateCheck.releasesPageURL)
                }
            }
            Divider()
            Text("Permissions")
                .font(.headline)
            if missing.isEmpty {
                Text("Lanterna has the permissions it needs.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("Grant the missing permissions, then restart Lanterna.")
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
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
