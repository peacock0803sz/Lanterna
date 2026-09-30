import SwiftUI

// MARK: - SettingsFilterView

/// The Filter tab: which windows reach the switcher list.
///
/// One picker per special window kind, each with a note on what the
/// choices do. Later filtering options join this tab.
struct SettingsFilterView: View {

  // MARK: Internal

  @Binding var values: SettingsValues

  var body: some View {
    Form {
      Section("Window types") {
        Picker(selection: $values.displayModes.otherSpace) {
          Text("Show").tag(DisplayMode.show)
          Text("Hide").tag(DisplayMode.hide)
          Text("Separate at bottom").tag(DisplayMode.separateAtBottom)
        } label: {
          SettingsFormLabel(
            title: "Windows on other spaces",
            caption: "Windows living on another Space: mix them in, keep them out, or park them below."
          )
        }
        .pickerStyle(.menu)
        Picker(selection: $values.displayModes.hiddenApp) {
          Text("Show").tag(DisplayMode.show)
          Text("Hide").tag(DisplayMode.hide)
          Text("Separate at bottom").tag(DisplayMode.separateAtBottom)
        } label: {
          SettingsFormLabel(
            title: "Windows of hidden apps",
            caption: "Windows of hidden applications: mix them in, keep them out, or park them below."
          )
        }
        .pickerStyle(.menu)
        Picker(selection: $values.displayModes.minimized) {
          Text("Show").tag(DisplayMode.show)
          Text("Hide").tag(DisplayMode.hide)
          Text("Separate at bottom").tag(DisplayMode.separateAtBottom)
        } label: {
          SettingsFormLabel(
            title: "Minimized windows",
            caption: "Windows folded into the Dock: mix them in, keep them out, or park them below."
          )
        }
        .pickerStyle(.menu)
        Picker(selection: $values.displayModes.fullscreen) {
          Text("Show").tag(DisplayMode.show)
          Text("Hide").tag(DisplayMode.hide)
          Text("Separate at bottom").tag(DisplayMode.separateAtBottom)
        } label: {
          SettingsFormLabel(
            title: "Fullscreen windows",
            caption: "Windows filling their own Space: mix them in, keep them out, or park them below."
          )
        }
        .pickerStyle(.menu)
      }
      Section("Search") {
        Picker(selection: $values.romajiScope) {
          Text("Kana only").tag(RomajiScope.kanaOnly)
          Text("Kana and kanji readings").tag(RomajiScope.kanaKanji)
        } label: {
          SettingsFormLabel(
            title: "Romaji matching",
            caption: "Match kana readings only, or kanji readings too."
          )
        }
        .pickerStyle(.menu)
        LabeledContent {
          HStack {
            Text(capText)
            Stepper(
              "Shortcut memory length",
              value: $values.shortcutMemoryLength,
              in: 0 ... 5
            )
            .labelsHidden()
          }
        } label: {
          SettingsFormLabel(
            title: "Shortcut memory length",
            caption: "Remember the chosen window per query up to this many characters. 0 means off."
          )
        }
        Toggle(isOn: $values.fuzzyMatchEnabled) {
          SettingsFormLabel(
            title: "Fuzzy matching",
            caption: "Match queries whose letters appear in order, not only substrings."
          )
        }
        Picker(selection: $values.resultOrder) {
          Text("MRU").tag(SearchOrdering.mru)
          Text("Best match").tag(SearchOrdering.score)
        } label: {
          SettingsFormLabel(
            title: "Result order",
            caption: "Show recent windows first, or best matches first."
          )
        }
        .pickerStyle(.menu)
      }
      Section {
        ForEach($values.exclusions) { $entry in
          ExclusionRow(entry: $entry) {
            if let index = values.exclusions.firstIndex(where: { $0.id == entry.id }) {
              values.exclusions.remove(at: index)
            }
          }
        }
        Button("Add excluded window") {
          values.exclusions.append(ExclusionEntry(app: "", titlePattern: ""))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      } header: {
        Text("Excluded windows")
      } footer: {
        VStack(alignment: .leading) {
          if hasInvalidRows {
            Text("Rows with an empty field or an unreadable app pattern are ignored.")
          }
          Text("A window stays out when its app and title both match a row. "
            + "The app field is matched as a regular expression. "
            + "A title wrapped as ^...$ must match exactly.")
        }
      }
    }
    .formStyle(.grouped)
    .settingsBackground()
  }

  // MARK: Private

  /// The cap as the stepper names it: a number, or off at zero.
  private var capText: String {
    values.shortcutMemoryLength == 0 ? "Off" : String(values.shortcutMemoryLength)
  }

  /// Whether any exclusion row would be skipped when showing.
  private var hasInvalidRows: Bool {
    values.exclusions.contains(where: {
      !WindowExclusion.isValid(app: $0.app, titlePattern: $0.titlePattern)
    })
  }

}

// MARK: - ExclusionRow

/// One exclusion row with its app icon and match note.
private struct ExclusionRow: View {

  // MARK: Lifecycle

  @MainActor
  init(entry: Binding<ExclusionEntry>, onRemove: @escaping () -> Void) {
    _entry = entry
    self.onRemove = onRemove
    // Seed cache from starting wording so first paint needs no extra pass.
    _resolved = State(initialValue: ExclusionAppResolver.resolve(app: entry.wrappedValue.app))
    _resolvedInput = State(initialValue: entry.wrappedValue.app)
  }

  // MARK: Internal

  @Binding var entry: ExclusionEntry

  let onRemove: () -> Void

  var body: some View {
    HStack(alignment: .top) {
      Image(nsImage: AppIconResolver.icon(forBundleIdentifier: resolved?.bundleIdentifier))
        .resizable()
        .frame(width: 22, height: 22)
      VStack(alignment: .leading) {
        TextField("App", text: $entry.app)
        if let resolved {
          Text("\(resolved.name) · \(resolved.bundleIdentifier)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        } else {
          Text("No matching app found")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        TextField("Title pattern", text: $entry.titlePattern)
      }
      Button("Remove", action: onRemove)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    .onChange(of: entry.app) { _, newValue in
      // Refresh cache only when this row wording alters, leaving other rows alone.
      guard newValue != resolvedInput else { return }
      resolvedInput = newValue
      resolved = ExclusionAppResolver.resolve(app: newValue)
    }
  }

  // MARK: Private

  @State private var resolved: ResolvedExclusionApp?
  @State private var resolvedInput: String

}
