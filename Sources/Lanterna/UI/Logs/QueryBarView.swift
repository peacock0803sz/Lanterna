import SwiftUI

// MARK: - QueryBarView

/// The query row beneath the toolbar, spanning the list width.
///
/// Holds either a lightweight filter string or a database
/// statement, never both. The mode switch asks the owner to
/// confirm when conditions would be lost, so this view never
/// discards text on its own. The guide beside the field keeps
/// the syntax beside the place it is typed.
struct QueryBarView: View {

  // MARK: Internal

  @Binding var query: LogQuery

  var queryFocused: FocusState<Bool>.Binding
  var onCommit: () -> Void
  var onModeSwitchRequest: (LogQuery.Mode) -> Void
  var timeLabel = ""
  var pendingFilteredCount = 0
  var isPaused = false
  var onRemoveChip: (String) -> Void = { _ in }
  var onClearAll: () -> Void = { }
  var onResumeFiltered: () -> Void = { }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        searchField
        modePicker
        guideButton
      }
      chipsRow
      pendingRow
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Query bar")
  }

  // MARK: Private

  @State private var showingGuide = false

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField(
        query.mode == .lightweight ? lightweightPlaceholder : databasePlaceholder,
        text: modeText,
        onCommit: onCommit
      )
      .textFieldStyle(.plain)
      .focused(queryFocused)
      .accessibilityLabel("Filter query")
      .accessibilityHint("Type a filter, press Return to apply")
      .disableAutocorrection(true)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(.quaternary.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }

  private var modeText: Binding<String> {
    Binding(
      get: {
        switch query.mode {
        case .lightweight: query.lightweightText
        case .database: query.databaseText
        }
      },
      set: { next in
        switch query.mode {
        case .lightweight: query.lightweightText = next
        case .database: query.databaseText = next
        }
      }
    )
  }

  private var modePicker: some View {
    Picker("Query mode", selection: modeSelection) {
      Text("Lightweight").tag(LogQuery.Mode.lightweight)
      Text("SQL").tag(LogQuery.Mode.database)
    }
    .pickerStyle(.segmented)
    .fixedSize()
    .accessibilityLabel("Query mode")
  }

  private var modeSelection: Binding<LogQuery.Mode> {
    Binding(
      get: { query.mode },
      set: { next in
        guard next != query.mode else { return }
        onModeSwitchRequest(next)
      }
    )
  }

  private var guideButton: some View {
    Button {
      showingGuide.toggle()
    } label: {
      Label("Query syntax", systemImage: "book.open")
    }
    .popover(isPresented: $showingGuide) {
      guideBody
        .padding()
        .frame(width: 380)
    }
    .accessibilityLabel("Query syntax guide")
    .accessibilityHint("Shows the filter syntax and statement limits")
  }

  private var guideBody: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Lightweight syntax")
        .font(.headline)
      Text(lightweightGuide)
        .font(.callout)
        .textSelection(.enabled)
      Divider()
      Text("Database mode")
        .font(.headline)
      Text(databaseGuide)
        .font(.callout)
        .textSelection(.enabled)
      Text(lightweightExample)
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Query syntax guide text")
  }

  private var lightweightPlaceholder: String {
    "Query — level>=warning cat:ax launch:current source.version:main app.bundle:com.vivaldi.Vivaldi \"text\""
  }

  private var databasePlaceholder: String {
    "SELECT seq, ts_ms FROM entries WHERE ts_ms >= … LIMIT 5000"
  }

  private var lightweightGuide: String {
    "Words separated by spaces must all match. Use field:value for contains, field=value for exact, field!=value to exclude. Levels compare in debug, info, warning, error order, as in level>=warn. Quote a phrase with \"…\". Dotted paths read nested fields, and [] matches any array element. Bound time with after: and before:."
  }

  private var databaseGuide: String {
    "Reads only: SELECT and WITH over the entries and launches columns. Every statement needs a time bound on ts_ms. A missing row cap is applied automatically. Writes are refused."
  }

  private var lightweightExample: String {
    "level>=warn category:ax \"AX\" app.bundle=com.vivaldi.Vivaldi"
  }

  private var parsedConditions: TranslatedFilter {
    LightweightFilter.parse(query.lightweightText)
  }

  private var visibleChips: [(original: String, display: String)] {
    let conditions = parsedConditions.conditions
    var out = [(String, String)]()
    let hasTime = conditions.contains {
      $0.chip.hasPrefix("After ") || $0.chip.hasPrefix("Before ")
    }
    if hasTime, !timeLabel.isEmpty {
      out.append(("__time__", "Time: \(timeLabel)"))
    }
    for condition in conditions {
      if condition.chip.hasPrefix("After ") || condition.chip.hasPrefix("Before ") {
        continue
      }
      out.append((condition.chip, displayName(for: condition.chip)))
    }
    return out
  }

  @ViewBuilder
  private var chipsRow: some View {
    if query.mode == .database {
      Text("Chips and toolbar filters stay off while SQL mode holds the statement.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Chips disabled in SQL mode")
    } else if !visibleChips.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(visibleChips, id: \.original) { entry in
            HStack(spacing: 4) {
              Text(entry.display)
                .font(.caption)
              Button {
                onRemoveChip(entry.original)
              } label: {
                Image(systemName: "xmark")
                  .font(.caption)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Remove filter \(entry.display)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.6))
            .clipShape(Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filter \(entry.display)")
          }
          Button("Clear All") {
            onClearAll()
          }
          .font(.caption)
          .accessibilityLabel("Clear All filters")
        }
      }
    }
  }

  @ViewBuilder
  private var pendingRow: some View {
    if isPaused, pendingFilteredCount > 0, query.mode == .lightweight {
      Button("\(pendingFilteredCount) new \u{00B7} Resume to show") {
        onResumeFiltered()
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .accessibilityLabel("\(pendingFilteredCount) new, resume to show")
    }
  }

  private func displayName(for chip: String) -> String {
    if chip == "Level: warning, error" {
      return "Level: Warnings & Errors"
    }
    return chip
  }

}
