import SwiftUI

/// One keyboard shortcut row: its name on the left, its keys on the right.
///
/// Presentation only; presses and edits flow back through the callbacks.
struct SettingsKeyboardRow: View {
  let action: KeyBindingAction

  @Binding var values: SettingsValues

  var isCapturing: Bool
  var onCapture: (Int?) -> Void
  var onRemove: (Int) -> Void
  var onReset: () -> Void
  var onCancel: () -> Void

  var body: some View {
    LabeledContent {
      HStack {
        ForEach(values.keyBindings[action], id: \.self) { key in
          Button(key.displayName) {
            onCapture(values.keyBindings[action].firstIndex(of: key))
          }
          .help("Press a replacement key")
          .contextMenu {
            Button("Remove") {
              if let slot = values.keyBindings[action].firstIndex(of: key) {
                onRemove(slot)
              }
            }
          }
        }
        Button {
          onCapture(nil)
        } label: {
          Image(systemName: "plus")
        }
        .help("Press an additional key")
        .accessibilityLabel("Add")
        Button {
          onReset()
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
        .help("Restore the default keys")
        .accessibilityLabel("Reset")
        if isCapturing {
          Button("Cancel") {
            onCancel()
          }
        }
      }
    } label: {
      SettingsFormLabel(
        title: KeyBindingCategory.displayName(for: action),
        caption: isCapturing ? "Press a key…" : nil
      )
    }
  }
}
