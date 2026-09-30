import SwiftUI

/// The Appearance tab: which look the windows use.
///
/// One picker for the single appearance value and one slider for the
/// text scale, each paired with its note on the label side.
struct SettingsAppearanceView: View {

  // MARK: Internal

  @Binding var values: SettingsValues

  var body: some View {
    Form {
      Section("Appearance") {
        Picker(selection: $values.appearanceMode) {
          Text("System").tag(AppearanceMode.system)
          Text("Light").tag(AppearanceMode.light)
          Text("Dark").tag(AppearanceMode.dark)
        } label: {
          SettingsFormLabel(
            title: "Appearance",
            caption: "Follow the system look, or stay light or dark."
          )
        }
        LabeledContent {
          Slider(value: textScaleIndex, in: 0 ... 4, step: 1) {
            Text("Text Size")
          } minimumValueLabel: {
            Text("Small")
          } maximumValueLabel: {
            Text("Large")
          }
        } label: {
          SettingsFormLabel(
            title: "Text Size",
            caption: "\(Int((values.textScale.factor * 100).rounded()))% of the standard size."
          )
        }
      }
    }
    .formStyle(.grouped)
  }

  // MARK: Private

  /// The slider position spelling the step: the slider works in
  /// doubles while the steps count in whole positions.
  private var textScaleIndex: Binding<Double> {
    Binding(
      get: { Double(values.textScale.rawValue) },
      set: { values.textScale = TextScaleLevel(rawValue: Int($0.rounded())) ?? .standard }
    )
  }

}
