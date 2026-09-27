import SwiftUI

/// The General tab: version and permission state.
///
/// Display-only, like the guide the permission part replaces: the state
/// is the launch-time snapshot, and a grant given mid-run waits for the
/// next launch. Future general options (launch at login, update checks)
/// join this tab.
struct SettingsGeneralView: View {
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
