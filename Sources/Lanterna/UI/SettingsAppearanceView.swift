import SwiftUI

// MARK: - SettingsAppearanceView

/// The Appearance tab: which look the windows use, and how large the
/// switcher text is.
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
      Section("Panel") {
        Picker(selection: $values.displayTarget) {
          Text("Primary display").tag(DisplayTarget.primary)
          Text("Display with cursor").tag(DisplayTarget.cursor)
          Text("Display with focused window").tag(DisplayTarget.frontWindow)
          Text("All displays").tag(DisplayTarget.all)
        } label: {
          SettingsFormLabel(
            title: "Show Panel on",
            caption: "Which display the panel opens on."
          )
        }
        .pickerStyle(.menu)
        LabeledContent {
          Slider(value: panelWidthIndex, in: 0 ... 4, step: 1) {
            Text("Panel Width")
          } minimumValueLabel: {
            Text("Narrow")
          } maximumValueLabel: {
            Text("Wide")
          }
          .labelsHidden()
          .tint(.accentColor)
        } label: {
          SettingsFormLabel(
            title: "Panel Width",
            caption: "\(Int((values.panelWidth.factor * 100).rounded()))% of the standard width."
          )
        }
        LabeledContent {
          HStack {
            Text(delayText)
            Stepper(
              "Show delay",
              value: delayMs,
              in: 0 ... ShowDelay.maximumMilliseconds,
              step: ShowDelay.settingsStep
            )
            .labelsHidden()
          }
        } label: {
          SettingsFormLabel(
            title: "Show delay",
            caption: "Wait this long before showing the panel. 0 means off."
          )
        }
        Toggle(isOn: $values.hoverSelect) {
          SettingsFormLabel(
            title: "Hover to select",
            caption: "Move the selection to the row under the pointer."
          )
        }
        Toggle(isOn: $values.scrollSelect) {
          SettingsFormLabel(
            title: "Scroll to select",
            caption: "Move the selection by scrolling. The view follows the selection."
          )
        }
        Toggle(isOn: $values.numberJump) {
          SettingsFormLabel(
            title: "Number jump",
            caption: "Jump to a row by its number while holding Command or Option. Off by default."
          )
        }
        Toggle(isOn: $values.numberReorder) {
          SettingsFormLabel(
            title: "Reorder rows",
            caption: "Move the selected row with Shift and arrow keys in grouped lists. Off by default."
          )
        }
        Picker(selection: $values.numberScope) {
          Text("Windows only").tag(NumberScope.windows)
          Text("All rows").tag(NumberScope.allRows)
        } label: {
          SettingsFormLabel(
            title: "Row numbers",
            caption: "Which rows row numbers cover."
          )
        }
        .pickerStyle(.menu)
      }
      Section("Preview") {
        preview
      }
    }
    .formStyle(.grouped)
    .settingsBackground()
  }

  // MARK: Private

  /// The preview draws at half the panel width: the full width never
  /// fits the settings window, and what the width switch needs to show
  /// is how one step compares to the next rather than full-size rows.
  private static let previewWidthRatio: CGFloat = 0.5

  /// The sample rows wearing the panel row look, following the chosen scale
  /// and look, ignoring clicks and reading as one preview element.
  private var preview: some View {
    let rows = Array(SampleWindows.standard().prefix(4))
    return VStack(spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.element.id) { index, window in
        WindowRow(
          window: window,
          isSelected: index == 1,
          // Numbers show the way the panel draws them while a jump
          // modifier is held; the reorder switch moves rows by key and
          // has no still picture, so only this switch reaches the preview.
          rowNumber: values.numberJump ? index + 1 : nil,
          query: "",
          textScale: values.textScale
        )
      }
    }
    .frame(width: PanelMetrics.width(for: values.textScale, step: values.panelWidth) * Self.previewWidthRatio)
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

  /// The delay stepper position spelling the milliseconds: nil reads
  /// as zero, and zero writes back as nil so off stays omitted on save.
  private var delayMs: Binding<Double> {
    Binding(
      get: { values.showDelayMs ?? 0 },
      set: { values.showDelayMs = $0 == 0 ? nil : $0 }
    )
  }

  /// The count as the stepper names it: a number, or off at zero.
  private var delayText: String {
    guard let milliseconds = values.showDelayMs, milliseconds > 0 else {
      return "Off"
    }
    return "\(Int(milliseconds)) ms"
  }

  /// The width slider position spelling the step, the same way the
  /// text size slider spells its step.
  private var panelWidthIndex: Binding<Double> {
    Binding(
      get: { Double(values.panelWidth.rawValue) },
      set: { values.panelWidth = PanelWidth(rawValue: Int($0.rounded())) ?? .standard }
    )
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
