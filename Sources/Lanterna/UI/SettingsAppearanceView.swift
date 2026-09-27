import SwiftUI

/// The Appearance tab: which look the windows use.
///
/// One picker for the single appearance value, with a note on what each
/// choice means. Future panel options (width, text size) join this tab.
struct SettingsAppearanceView: View {
    @Binding var values: SettingsValues

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Picker("Appearance", selection: $values.appearanceMode) {
                    Text("System").tag(AppearanceMode.system)
                    Text("Light").tag(AppearanceMode.light)
                    Text("Dark").tag(AppearanceMode.dark)
                }
                Text("Follow the system look, or stay light or dark.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
