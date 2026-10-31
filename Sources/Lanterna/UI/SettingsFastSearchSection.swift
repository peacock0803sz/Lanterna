import SwiftUI

// MARK: - SettingsFastSearchSection

/// The Filter tab's Fast Search section: which held keys start a search
/// with no panel open, and whether typing in a switcher panel starts a
/// filter.
///
/// The wording says what each key gives up, since an enabled key keeps its
/// letters from every application while it is held.
struct SettingsFastSearchSection: View {

  // MARK: Internal

  @Binding var values: SettingsValues

  var body: some View {
    Section {
      LabeledContent {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
          ForEach(Self.rows, id: \.self) { row in
            GridRow {
              ForEach(row, id: \.self) { modifier in
                Toggle(modifier.displayName, isOn: binding(for: modifier))
              }
            }
          }
        }
      } label: {
        SettingsFormLabel(title: "Fast Search with", caption: Self.usage)
      }
      Text(Self.notes)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Toggle(isOn: $values.typingStartsFiltering) {
        SettingsFormLabel(title: "Typing starts filtering in the panel", caption: Self.typingNote)
      }
    } header: {
      Text("Fast Search")
    }
  }

  // MARK: Private

  /// The toggle grid's rows: Fn and Caps Lock, then each side of Command,
  /// then Option.
  private static let rows: [[FastSearchModifier]] = [
    [.fn, .capsLock],
    [.leftCommand, .rightCommand],
    [.leftOption, .rightOption],
  ]

  private static let usage = "Hold an enabled key and type a few letters of an app name or window title. "
    + "The panel shows the matches; let go of the key to switch to the selected window."

  private static let notes = [
    "Caps Lock works only after System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys "
      + "sets the Caps Lock key to Escape. With Caps Lock enabled, the Escape key itself works the same way: "
      + "pressed alone, it is sent when you let go, and a letter typed before you let go starts Fast Search, "
      + "even when you meant Escape followed by that letter.",
    "With a Command or Option key enabled, letters typed while holding that key no longer reach apps "
      + "as shortcuts or special characters.",
    "With Fn enabled, Fn combinations the system uses, such as Fn-Q for Quick Note and Fn-E for emoji, "
      + "still go to the system when typed first.",
    "Letting go of Fn after a search may also trigger the action set for the Globe key. "
      + "Set \"Press 🌐 key to\" to \"Do Nothing\" in System Settings > Keyboard to avoid it.",
  ].joined(separator: "\n\n")

  private static let typingNote = "When on, typing in a panel opened with Command-Tab or Option-Tab starts filtering, "
    + "and letting go switches to the selected window. J, K, N, P and S type letters, and window actions "
    + "such as Command-W need a press and hold. The letter of such a key appears when you let go of it "
    + "or type the next key."

  private func binding(for modifier: FastSearchModifier) -> Binding<Bool> {
    Binding(
      get: { values.fastSearchModifiers.contains(modifier) },
      set: { isOn in
        if isOn {
          values.fastSearchModifiers.insert(modifier)
        } else {
          values.fastSearchModifiers.remove(modifier)
        }
      }
    )
  }

}
