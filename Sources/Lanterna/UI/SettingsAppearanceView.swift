import SwiftUI

/// The Appearance tab: which look the windows use.
///
/// One picker for the single appearance value. Future panel options
/// (width, text size) join this tab.
struct SettingsAppearanceView: View {
    @Binding var values: SettingsValues

    var body: some View {
        Form {
            Picker("Appearance", selection: $values.appearanceMode) {
                Text("System").tag(AppearanceMode.system)
                Text("Light").tag(AppearanceMode.light)
                Text("Dark").tag(AppearanceMode.dark)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
