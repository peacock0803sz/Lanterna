import SwiftUI

// MARK: - TimeRangeView

/// The toolbar time picker content.
///
/// Three kinds: now-relative presets plus a custom Last span,
/// an anchored Around, Before, or After span with a readable
/// preview, and a fixed Custom range. The draft only reaches the
/// window on Apply, so opening and cancelling changes nothing.
struct TimeRangeView: View {

  // MARK: Internal

  @Binding var selection: TimeRangeSelection

  var launchStart: Date?
  var onApply: (TimeRangeSelection) -> Void
  var onReset: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      relativeSection
      Divider()
      anchoredSection
      Divider()
      customSection
      previewRow
      actionRow
    }
    .padding(14)
    .frame(width: 360)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Time Range picker")
  }

  // MARK: Private

  @State private var draft: TimeRangeSelection?
  @State private var lastText = "15"

  private var working: Binding<TimeRangeSelection> {
    Binding(
      get: { draft ?? selection },
      set: { draft = $0 }
    )
  }

  private var resolved: TimeRangeResolve {
    TimeRangeResolver.resolve(working.wrappedValue, launchStart: launchStart)
  }

  private var relativeSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Relative to now")
        .font(.headline)
        .accessibilityLabel("Relative to now")
      presetRow
      lastRow
      HStack(spacing: 8) {
        Button("Since this launch") {
          var next = working.wrappedValue
          next.kind = .relativeNow
          next.relative = .sinceLaunch
          working.wrappedValue = next
        }
        .accessibilityLabel("Since this launch")
        Button("All kept") {
          var next = working.wrappedValue
          next.kind = .relativeNow
          next.relative = .allKept
          working.wrappedValue = next
        }
        .accessibilityLabel("All kept")
      }
      .font(.callout)
      Text("or pick a preset above")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var presetRow: some View {
    HStack(spacing: 6) {
      presetButton(title: "5m", choice: .presetFiveMinutes)
      presetButton(title: "15m", choice: .presetQuarterHour)
      presetButton(title: "1h", choice: .presetHour)
      presetButton(title: "6h", choice: .presetSixHours)
      presetButton(title: "24h", choice: .presetDay)
      presetButton(title: "7d", choice: .presetWeek)
    }
  }

  private var lastRow: some View {
    HStack(spacing: 6) {
      Text("Last")
      TextField("Amount", text: lastBinding)
        .textFieldStyle(.roundedBorder)
        .frame(width: 56)
        .accessibilityLabel("Last amount")
      Picker("Unit", selection: lastUnitBinding) {
        ForEach(TimeSpanUnit.allCases, id: \.self) { unit in
          Text(unit.rawValue).tag(unit)
        }
      }
      .pickerStyle(.menu)
      .accessibilityLabel("Last unit")
    }
    .font(.callout)
    .onAppear {
      lastText = String(working.wrappedValue.lastAmount)
    }
  }

  private var lastBinding: Binding<String> {
    Binding(
      get: { lastText },
      set: { next in
        lastText = next
        if let amount = Int(next), amount > 0 {
          var draftValue = working.wrappedValue
          draftValue.kind = .relativeNow
          draftValue.lastAmount = amount
          draftValue.relative = .last(amount: amount, unit: draftValue.lastUnit)
          working.wrappedValue = draftValue
        }
      }
    )
  }

  private var lastUnitBinding: Binding<TimeSpanUnit> {
    Binding(
      get: { working.wrappedValue.lastUnit },
      set: { next in
        var draftValue = working.wrappedValue
        draftValue.kind = .relativeNow
        draftValue.lastUnit = next
        let amount = Int(lastText) ?? draftValue.lastAmount
        draftValue.lastAmount = max(amount, 1)
        draftValue.relative = .last(amount: draftValue.lastAmount, unit: next)
        working.wrappedValue = draftValue
      }
    )
  }

  private var anchoredSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Relative to a time")
        .font(.headline)
      Picker("Anchor style", selection: anchoredStyleBinding) {
        ForEach(AnchoredStyle.allCases, id: \.self) { style in
          Text(style.title).tag(style)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityLabel("Around Before After")
      DatePicker("Anchor", selection: anchorBinding, displayedComponents: [.date, .hourAndMinute])
        .accessibilityLabel("Anchor time")
      HStack(spacing: 6) {
        Text("Span")
        TextField("Span", text: spanBinding)
          .textFieldStyle(.roundedBorder)
          .frame(width: 56)
          .accessibilityLabel("Span amount")
        Picker("Span unit", selection: spanUnitBinding) {
          ForEach(TimeSpanUnit.allCases, id: \.self) { unit in
            Text(unit.rawValue).tag(unit)
          }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Span unit")
      }
      .font(.callout)
      Text(
        "Any amount in seconds, minutes, hours or days. Before and After take the span on one side only. The anchor can also be set from a histogram bar or a selected row."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var anchoredStyleBinding: Binding<AnchoredStyle> {
    Binding(
      get: { working.wrappedValue.anchoredStyle },
      set: { next in
        var draftValue = working.wrappedValue
        draftValue.kind = .anchored
        draftValue.anchoredStyle = next
        working.wrappedValue = draftValue
      }
    )
  }

  private var anchorBinding: Binding<Date> {
    Binding(
      get: { working.wrappedValue.anchor },
      set: { next in
        var draftValue = working.wrappedValue
        draftValue.kind = .anchored
        draftValue.anchor = next
        working.wrappedValue = draftValue
      }
    )
  }

  private var spanBinding: Binding<String> {
    Binding(
      get: { String(working.wrappedValue.spanAmount) },
      set: { next in
        if let amount = Int(next), amount > 0 {
          var draftValue = working.wrappedValue
          draftValue.kind = .anchored
          draftValue.spanAmount = amount
          working.wrappedValue = draftValue
        }
      }
    )
  }

  private var spanUnitBinding: Binding<TimeSpanUnit> {
    Binding(
      get: { working.wrappedValue.spanUnit },
      set: { next in
        var draftValue = working.wrappedValue
        draftValue.kind = .anchored
        draftValue.spanUnit = next
        working.wrappedValue = draftValue
      }
    )
  }

  private var customSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Custom range")
        .font(.headline)
      DatePicker("Start", selection: customStartBinding, displayedComponents: [.date, .hourAndMinute])
        .accessibilityLabel("Custom range start")
      DatePicker("End", selection: customEndBinding, displayedComponents: [.date, .hourAndMinute])
        .accessibilityLabel("Custom range end")
    }
  }

  private var customStartBinding: Binding<Date> {
    Binding(
      get: { working.wrappedValue.customStart },
      set: { next in
        var draftValue = working.wrappedValue
        draftValue.kind = .custom
        draftValue.customStart = next
        working.wrappedValue = draftValue
      }
    )
  }

  private var customEndBinding: Binding<Date> {
    Binding(
      get: { working.wrappedValue.customEnd },
      set: { next in
        var draftValue = working.wrappedValue
        draftValue.kind = .custom
        draftValue.customEnd = next
        working.wrappedValue = draftValue
      }
    )
  }

  private var previewRow: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(resolved.shortLabel)
        .font(.callout)
        .fontWeight(.semibold)
        .accessibilityLabel("Resolved range \(resolved.shortLabel)")
      Text(resolved.preview)
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .accessibilityLabel("Resolved bounds \(resolved.preview)")
    }
  }

  private var actionRow: some View {
    HStack {
      Button("Reset Time Range") {
        onReset()
      }
      .accessibilityLabel("Reset Time Range")
      Spacer()
      Button("Apply") {
        onApply(working.wrappedValue)
      }
      .buttonStyle(.borderedProminent)
      .accessibilityLabel("Apply time range")
      .keyboardShortcut(.defaultAction)
    }
  }

  private func presetButton(title: String, choice: RelativeNowChoice) -> some View {
    Button(title) {
      var next = working.wrappedValue
      next.kind = .relativeNow
      next.relative = choice
      working.wrappedValue = next
    }
    .buttonStyle(.bordered)
    .font(.callout)
    .accessibilityLabel("Last \(title)")
  }

}
