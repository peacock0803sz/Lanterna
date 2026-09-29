import SwiftUI

/// The Appearance tab: which look the windows use.
///
/// One picker for the single appearance value, with a note on what each
/// choice means. Future panel options (width) join this tab.
struct SettingsAppearanceView: View {
    @Binding var values: SettingsValues

    /// The slider position spelling the step: the slider works in
    /// doubles while the steps count in whole positions.
    private var textScaleIndex: Binding<Double> {
        Binding(
            get: { Double(values.textScale.rawValue) },
            set: { values.textScale = TextScaleLevel(rawValue: Int($0.rounded())) ?? .standard }
        )
    }

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
            VStack(alignment: .leading, spacing: 4) {
                Slider(value: textScaleIndex, in: 0 ... 4, step: 1) {
                    Text("Text Size")
                } minimumValueLabel: {
                    Text("Small")
                } maximumValueLabel: {
                    Text("Large")
                }
                Text("\(Int((values.textScale.factor * 100).rounded()))% of the standard size.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
