import SwiftUI

/// The General tab: launch behavior, version, and permission state.
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
