import SwiftUI

// MARK: - JumpToTimeView

/// An exact jump to the nearest entry.
///
/// The calendar stays within the kept days, from the oldest
/// retained launch day through today. The fixed date and time
/// fields mirror the calendar both ways: picking a day rewrites
/// the fields, and typing rewrites the calendar. Time reads as
/// hours, minutes, seconds, with optional milliseconds, and the
/// stepper beside it moves by second with the arrow keys.
struct JumpToTimeView: View {

  // MARK: Internal

  var oldestDay: Date
  var newestDay: Date
  var initial: Date
  var onJump: (Date) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Jump to Time")
        .font(.headline)
        .accessibilityLabel("Jump to Time")
      DatePicker(
        "Calendar",
        selection: $chosen,
        in: dayFloor(of: oldestDay) ... endOfDay(of: newestDay),
        displayedComponents: [.date]
      )
      .datePickerStyle(.graphical)
      .accessibilityLabel("Calendar, from oldest kept day to today")
      .onChange(of: chosen) { _, next in
        syncFields(from: next)
      }
      HStack(spacing: 8) {
        TextField("Date yyyy-MM-dd", text: dateText)
          .textFieldStyle(.roundedBorder)
          .frame(width: 110)
          .accessibilityLabel("Date, year month day")
        TextField("Time HH:MM:SS.mmm", text: clockText)
          .textFieldStyle(.roundedBorder)
          .frame(width: 130)
          .accessibilityLabel("Time, hours minutes seconds, milliseconds optional")
        Stepper("Step time", value: $stepCount, step: 1)
          .labelsHidden()
          .accessibilityLabel("Step time by second")
          .onChange(of: stepCount) { _, next in
            chosen = chosen.addingTimeInterval(Double(next - previousStep))
            previousStep = next
            syncFields(from: chosen)
          }
      }
      Text(hintText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel(hintText)
      Text(previewText)
        .font(.callout)
        .textSelection(.enabled)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Jump") {
          onJump(chosen)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel("Jump to nearest entry")
      }
    }
    .padding(16)
    .frame(width: 340)
    .onAppear {
      chosen = initial
      syncFields(from: initial)
    }
  }

  // MARK: Private

  @Environment(\.dismiss) private var dismiss
  @State private var chosen = Date()
  @State private var dateBox = ""
  @State private var clockBox = ""
  @State private var stepCount = 0
  @State private var previousStep = 0

  private var dateText: Binding<String> {
    Binding(
      get: { dateBox },
      set: { next in
        dateBox = next
        if let rebuilt = combine(date: next, clock: clockBox) {
          chosen = rebuilt
        }
      }
    )
  }

  private var clockText: Binding<String> {
    Binding(
      get: { clockBox },
      set: { next in
        clockBox = next
        if let rebuilt = combine(date: dateBox, clock: next) {
          chosen = rebuilt
        }
      }
    )
  }

  private var hintText: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMM d"
    let oldest = formatter.string(from: oldestDay)
    return "Days with kept logs (\(oldest) – today) can be picked. Type the time or step it with arrows; milliseconds are optional. The nearest entry is selected."
  }

  private var previewText: String {
    LogExport.fullTime(milliseconds: Int64(chosen.timeIntervalSince1970 * 1_000))
  }

  private func syncFields(from date: Date) {
    let dayFormatter = DateFormatter()
    dayFormatter.locale = Locale(identifier: "en_US_POSIX")
    dayFormatter.dateFormat = "yyyy-MM-dd"
    let clockFormatter = DateFormatter()
    clockFormatter.locale = Locale(identifier: "en_US_POSIX")
    clockFormatter.dateFormat = "HH:mm:ss.SSS"
    dateBox = dayFormatter.string(from: date)
    clockBox = clockFormatter.string(from: date)
  }

  private func combine(date: String, clock: String) -> Date? {
    let trimmedClock = clock.trimmingCharacters(in: .whitespaces)
    let formats = ["yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for format in formats {
      formatter.dateFormat = format
      if let date = formatter.date(from: "\(date) \(trimmedClock)") {
        return date
      }
      if trimmedClock.isEmpty, format == "yyyy-MM-dd" {
        if let date = formatter.date(from: date) {
          return date
        }
      }
    }
    return nil
  }

  private func dayFloor(of date: Date) -> Date {
    Calendar.current.startOfDay(for: date)
  }

  private func endOfDay(of date: Date) -> Date {
    let floor = Calendar.current.startOfDay(for: date)
    return Calendar.current.date(byAdding: .day, value: 1, to: floor)?.addingTimeInterval(-1) ?? date
  }

}
