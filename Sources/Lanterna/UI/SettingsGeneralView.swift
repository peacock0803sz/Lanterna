import SwiftUI

/// The General tab: permission state and nothing else.
///
/// Display-only, like the guide it replaces: the state is the launch-time
/// snapshot, and a grant given mid-run waits for the next launch. Future
/// general options (launch at login, update checks) join this tab.
struct SettingsGeneralView: View {
    let missing: [MissingPermission]
    let opener: SettingsOpener

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
