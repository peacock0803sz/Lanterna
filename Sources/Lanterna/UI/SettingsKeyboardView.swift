import AppKit
import SwiftUI

/// The Keyboard tab: categories and search on the left, rows on the right.
///
/// Rows read from the shared values and write back through them, like
/// every other tab. An invalid press never reaches the values: the row
/// says why and keeps the old keys, so the file can never be saved
/// invalid from here.
struct SettingsKeyboardView: View {

  // MARK: Internal

  @Binding var values: SettingsValues

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      detail
    }
    .onDisappear(perform: stopCapture)
    .onChange(of: searchText) { _, _ in stopCapture() }
    .onChange(of: selectedCategory) { _, _ in stopCapture() }
  }

  // MARK: Private

  /// The category the sidebar shows as chosen outside a search.
  @State private var selectedCategory = KeyBindingCategory.switcher

  /// The sidebar search wording, empty outside a search.
  @State private var searchText = ""

  /// The row waiting for a press, and which slot a press replaces.
  /// A `nil` slot appends instead.
  @State private var capturing: (action: KeyBindingAction, slot: Int?)?
  @State private var capture = KeyCaptureMonitor()
  @State private var notice: String?

  /// Search focus ends capture so typing reaches search.
  @FocusState private var searchFocused: Bool

  /// The found rows for the search wording, or nil outside a search.
  private var found: [(category: KeyBindingCategory, actions: [KeyBindingAction])]? {
    KeyBindingCategory.matches(searchText)
  }

  /// The sidebar selection, hidden while searching. Choosing a category
  /// ends the search.
  private var sidebarSelection: Binding<KeyBindingCategory?> {
    Binding(
      get: { found == nil ? selectedCategory : nil },
      set: {
        guard let next = $0 else { return }
        if found != nil {
          searchText = ""
        }
        selectedCategory = next
      }
    )
  }

  /// The categories and their search field.
  private var sidebar: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("Search shortcuts", text: $searchText)
          .textFieldStyle(.plain)
          .focused($searchFocused)
          .onChange(of: searchFocused) { _, focused in
            if focused {
              stopCapture()
            }
          }
        if !searchText.isEmpty {
          Button {
            searchText = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color(nsColor: .controlBackgroundColor))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(.separator)
      }
      .padding(8)
      List(selection: sidebarSelection) {
        ForEach(KeyBindingCategory.allCases, id: \.self) { category in
          HStack {
            Image(systemName: category.iconName)
            Text(category.title)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
            Spacer()
            Text("\(category.actions.count)")
              .foregroundStyle(.secondary)
          }
          .tag(category)
          .listRowBackground(Color.clear)
        }
      }
      .settingsSidebarBackground()
    }
    .frame(width: 170)
    .settingsSidebarBackground()
  }

  /// The heading above the detail rows.
  private var detailTitle: String {
    guard let found else { return selectedCategory.title }
    let count = found.reduce(0) { $0 + $1.actions.count }
    if count == 0 {
      return "0 results for “\(searchText)”."
    } else if count == 1 {
      return "1 result for “\(searchText)”."
    } else {
      return "\(count) results for “\(searchText)”."
    }
  }

  /// The detail rows with their heading and footer.
  private var detail: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(detailTitle)
        .font(.headline)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
      Form {
        if let found {
          if found.isEmpty {
            Text("No shortcuts match “\(searchText)”.")
          } else {
            ForEach(found, id: \.category) { entry in
              Section(entry.category.title) {
                ForEach(entry.actions, id: \.self) { action in
                  row(for: action)
                }
              }
            }
          }
        } else {
          Section {
            ForEach(selectedCategory.actions, id: \.self) { action in
              row(for: action)
            }
          }
        }
      }
      .formStyle(.grouped)
      .settingsBackground()
      HStack {
        Button("Reset all") {
          values.keyBindings = .defaults
          stopCapture()
          notice = nil
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        if let notice {
          Text(notice)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 8)
      Text(
        "Press a key to assign it. Assignments are physical keys, independent of input source. Letter and number keys with no modifier act only while not filtering; while filtering they type into the query."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 20)
      .padding(.bottom, 8)
    }
    .background(Color(nsColor: .underPageBackgroundColor))
  }

  /// One action's row, wired to the capture below.
  private func row(for action: KeyBindingAction) -> some View {
    SettingsKeyboardRow(
      action: action,
      values: $values,
      isCapturing: capturing?.action == action,
      onCapture: { startCapture(action, slot: $0) },
      onRemove: { removeKey(action: action, at: $0) },
      onReset: {
        values.keyBindings.keys[action] = KeyBindingTable.defaults[action]
        stopCapture()
        notice = nil
      },
      onCancel: {
        stopCapture()
        notice = nil
      }
    )
  }

  /// Removes one key. Removing the last key restores the row's defaults
  /// with a notice, because an emptied row would read as defaults
  /// downstream while looking empty here.
  private func removeKey(action: KeyBindingAction, at index: Int) {
    stopCapture()
    var keys = values.keyBindings[action]
    guard keys.indices.contains(index) else { return }
    keys.remove(at: index)
    if keys.isEmpty {
      keys = KeyBindingTable.defaults[action]
      notice = "Removing the last key restored \(KeyBindingCategory.displayName(for: action)) defaults."
    } else {
      notice = nil
    }
    values.keyBindings.keys[action] = keys
  }

  /// Arms the capture: the next key down in this window goes to this row.
  /// The row is clicked to arm, so the key window is this one.
  private func startCapture(_ action: KeyBindingAction, slot: Int?) {
    stopCapture()
    capturing = (action, slot)
    notice = nil
    capture.arm(in: NSApp.keyWindow) { event in
      assign(action: action, slot: slot, keyCode: event.keyCode, modifiers: event.modifierFlags)
    }
  }

  /// Takes the capture down. A press that arrived stays assigned;
  /// only the waiting ends here.
  private func stopCapture() {
    capture.disarm()
    capturing = nil
  }

  /// Assigns the pressed key, refusing what the table would refuse.
  /// Only the four schema modifiers count: anything else the keyboard
  /// reports with the press is narrowed away first. The rules themselves
  /// live with the table, so this only words the refusal.
  private func assign(
    action: KeyBindingAction,
    slot: Int?,
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags
  ) {
    let narrowed = modifiers.intersection([.shift, .control, .option, .command])
    let key = ResolvedKey(keyCode: keyCode, modifiers: narrowed)
    let row = KeyBindingCategory.displayName(for: action)
    switch KeyBindingTable.refusal(assigning: key, to: action, in: values.keyBindings) {
    case .none:
      break

    case .needsModifiers:
      notice = "\(key.displayName) needs Cmd, Ctrl or Opt for \(row)."
      stopCapture()
      return

    case .alreadyHeld:
      notice = "\(row) already holds \(key.displayName)."
      stopCapture()
      return

    case .heldBy(let holders):
      let names = holders.lazy.map { KeyBindingCategory.displayName(for: $0) }.joined(separator: ", ")
      notice = "\(key.displayName) is already used by \(names); not added to \(row)."
      stopCapture()
      return
    }
    var keys = values.keyBindings[action]
    if let slot, keys.indices.contains(slot) {
      keys[slot] = key
    } else {
      keys.append(key)
    }
    values.keyBindings.keys[action] = keys
    stopCapture()
    notice = nil
  }

}
