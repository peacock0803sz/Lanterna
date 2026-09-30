import SwiftUI

// MARK: - SettingsAppearanceView

/// The Appearance tab: which look the windows use.
///
/// The look and the text size are chosen above, and a preview below
/// shows sample switcher rows with both applied.
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
        .pickerStyle(.menu)
        LabeledContent {
          Slider(value: textScaleIndex, in: 0 ... 4, step: 1) {
            Text("Text Size")
          } minimumValueLabel: {
            Text("Small")
          } maximumValueLabel: {
            Text("Large")
          }
          .labelsHidden()
          .tint(.accentColor)
        } label: {
          SettingsFormLabel(
            title: "Text Size",
            caption: "\(Int((values.textScale.factor * 100).rounded()))% of the standard size."
          )
        }
      }
      Section("Preview") {
        preview
      }
    }
    .formStyle(.grouped)
    .settingsBackground()
  }

  // MARK: Private

  /// The sample rows wearing the panel row look, following the chosen scale
  /// and look, ignoring clicks and reading as one preview element.
  private var preview: some View {
    let rows = Array(SampleWindows.standard().prefix(4))
    return VStack(spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.element.id) { index, window in
        WindowRow(
          window: window,
          isSelected: index == 1,
          query: "",
          textScale: values.textScale
        )
      }
    }
    .padding(.vertical, 6)
    .adaptiveGlass(cornerRadius: 16)
    .background {
      RoundedRectangle(cornerRadius: 16)
        .fill(Color.secondary.opacity(0.12))
    }
    .allowsHitTesting(false)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Preview")
    .appliedAppearance(values.appearanceMode)
  }

  /// The slider position spelling the step: the slider works in
  /// doubles while the steps count in whole positions.
  private var textScaleIndex: Binding<Double> {
    Binding(
      get: { Double(values.textScale.rawValue) },
      set: { values.textScale = TextScaleLevel(rawValue: Int($0.rounded())) ?? .standard }
    )
  }

}

// MARK: - View + appliedAppearance

/// Follows the chosen look, leaving system choice to the system.
extension View {
  @ViewBuilder
  fileprivate func appliedAppearance(_ mode: AppearanceMode) -> some View {
    if mode == .light {
      environment(\.colorScheme, .light)
    } else if mode == .dark {
      environment(\.colorScheme, .dark)
    } else {
      self
    }
  }
}
