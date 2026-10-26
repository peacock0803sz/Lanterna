import SwiftUI

// MARK: - SettingsFilterView

/// The Filter tab: how the query matches and orders the windows, and
/// which windows stay out of every list.
///
/// Search tunes matching and result order, and sets how long a query
/// may be for the window last chosen with it to come first again.
/// Excluded windows keep matching windows out altogether. Which kinds
/// of windows each switcher lists lives in the Switchers tab.
struct SettingsFilterView: View {

  // MARK: Internal

  @Binding var values: SettingsValues

  var body: some View {
    Form {
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
        Picker(selection: $values.forcedInputSource) {
          Text("Off").tag(String?.none)
          ForEach(inputSourceChoices) { choice in
            Text(choice.name).tag(Optional(choice.id))
          }
        } label: {
          SettingsFormLabel(
            title: "Force keyboard",
            caption: "Switch to this input source while the panel is up."
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

  /// What the input menu offers, plus the stored ID when it no longer
  /// does, so the picker never shows blank. Read on each pass, which also
  /// picks up a source enabled while the window is open.
  private var inputSourceChoices: [InputSourceChoice] {
    let choices = InputSourceLock.selectableSources()
    guard let stored = values.forcedInputSource, !choices.contains(where: { $0.id == stored }) else {
      return choices
    }
    return choices + [InputSourceChoice(id: stored, name: stored)]
  }

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

  init(entry: Binding<ExclusionEntry>, onRemove: @escaping () -> Void) {
    _entry = entry
    self.onRemove = onRemove
  }

  // MARK: Internal

  @Binding var entry: ExclusionEntry

  let onRemove: () -> Void

  var body: some View {
    HStack(alignment: .top) {
      Image(nsImage: AppIconResolver.icon(forBundleIdentifier: resolution.app?.bundleIdentifier))
        .resizable()
        .frame(width: 22, height: 22)
      VStack(alignment: .leading) {
        TextField("App", text: $entry.app)
        Text(resolution.note)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        TextField("Title pattern", text: $entry.titlePattern)
      }
      Button("Remove", action: onRemove)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    .task(id: entry.app) {
      // Runs when the row appears and when its app wording changes, not on
      // every parent pass.
      resolution = ExclusionAppResolver.resolve(app: entry.app).map(Resolution.found) ?? .none
    }
  }

  // MARK: Private

  /// The looked-up app, kept until the row appears again or its app
  /// wording changes.
  @State private var resolution = Resolution.pending

}

// MARK: ExclusionRow.Resolution

extension ExclusionRow {
  /// Whether the row's app has been looked up yet, and what came back.
  fileprivate enum Resolution {
    case pending
    case none
    case found(ResolvedExclusionApp)

    // MARK: Internal

    var app: ResolvedExclusionApp? {
      if case .found(let app) = self {
        app
      } else {
        nil
      }
    }

    /// The note under the app field, blank until the first lookup lands.
    /// The note line is laid out even while blank, so the row does not
    /// grow when the note arrives.
    var note: String {
      switch self {
      case .pending: ""
      case .none: "No installed bundle ID or running app matched"
      case .found(let app): "\(app.name) · \(app.bundleIdentifier)"
      }
    }
  }
}
