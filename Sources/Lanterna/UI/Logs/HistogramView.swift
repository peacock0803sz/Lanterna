import SwiftUI

// MARK: - HistogramBucket

/// One time slice in the histogram.
struct HistogramBucket: Equatable {
  var startMilliseconds: Int64
  var endMilliseconds: Int64
  var filteredCount: Int
  var totalCount: Int
  var errorCount: Int
  var warningCount: Int
  var holdsSelection: Bool
}

// MARK: - HistogramView

/// The time distribution above the table.
///
/// Covers every launch in the list. Matching buckets keep their
/// level colours while the rest fade, and the bucket holding the
/// selected row gets an outline. The disclosure folds it to one
/// line of sparkline, counts, and span; the folded state survives
/// reopening through the owner's stored flag. While a row stays
/// selected the chart drops to a compact strip so the list and
/// the detail keep their room.
struct HistogramView: View {

  // MARK: Internal

  var filteredRows: [DiagnosticRow]
  var totalRows: [DiagnosticRow]
  var launchCount: Int
  var selectedRowID: String?
  var isCompact: Bool

  @Binding var isCollapsed: Bool

  var onJumpToMilliseconds: (Int64) -> Void = { _ in }
  var onShowInterval: (Int64, Int64) -> Void = { _, _ in }
  var onShowLaunch: (String) -> Void = { _ in }
  var onResetTime: () -> Void = { }
  var onCopyInterval: (Int64, Int64) -> Void = { _, _ in }
  var onOpenJumpDialog: () -> Void = { }

  var body: some View {
    VStack(spacing: 0) {
      if isCollapsed {
        collapsedRow
      } else if isCompact {
        compactStrip
      } else {
        openChart
      }
    }
    .background(.quaternary.opacity(0.25))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Histogram")
  }

  static func buckets(
    filtered: [DiagnosticRow],
    total: [DiagnosticRow],
    selectedRowID: String?,
    bucketLimit: Int
  ) -> [HistogramBucket] {
    let span = total.isEmpty ? filtered : total
    guard
      let earliest = span.map(\.recordedAtMilliseconds).min(),
      let latest = span.map(\.recordedAtMilliseconds).max()
    else {
      return []
    }
    let safeSpan = max(latest - earliest, 1_000)
    let width = max(safeSpan / Int64(max(bucketLimit, 1)), 1_000)
    var out = [HistogramBucket]()
    var cursor = earliest
    while cursor <= latest {
      let end = min(cursor + width, latest + 1)
      let inFiltered = filtered.filter { $0.recordedAtMilliseconds >= cursor && $0.recordedAtMilliseconds < end }
      let inTotal = total.isEmpty
        ? inFiltered
        : total.filter { $0.recordedAtMilliseconds >= cursor && $0.recordedAtMilliseconds < end }
      let errors = inFiltered.count(where: { $0.level == "error" })
      let warnings = inFiltered.count(where: { $0.level == "warning" })
      let holds = selectedRowID.map { wanted in
        inFiltered.contains { $0.rowID == wanted }
      } ?? false
      out.append(
        HistogramBucket(
          startMilliseconds: cursor,
          endMilliseconds: end,
          filteredCount: inFiltered.count,
          totalCount: max(inTotal.count, inFiltered.count),
          errorCount: errors,
          warningCount: warnings,
          holdsSelection: holds
        )
      )
      cursor = end
    }
    return out
  }

  // MARK: Private

  @State private var hoveredIndex: Int?

  private var buckets: [HistogramBucket] {
    HistogramView.buckets(
      filtered: filteredRows,
      total: totalRows,
      selectedRowID: selectedRowID,
      bucketLimit: 40
    )
  }

  private var selectedBucket: HistogramBucket? {
    buckets.first { $0.holdsSelection }
  }

  private var openChart: some View {
    VStack(spacing: 3) {
      HStack(spacing: 8) {
        collapseButton
        barsRow(height: 32)
      }
      .padding(.horizontal, 14)
      .padding(.top, 8)
      axisRow
      hoverHint
    }
    .padding(.bottom, 6)
  }

  private var compactStrip: some View {
    HStack(spacing: 8) {
      collapseButton
      barsRow(height: 14)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 6)
    .accessibilityLabel("Histogram compact strip while detail shows")
  }

  private var collapsedRow: some View {
    HStack(spacing: 8) {
      collapseButton
      sparkline
      Text(summaryText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel(summaryText)
      Spacer()
      if selectedBucket != nil {
        Text("selected outlined")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Button("Expand") {
        isCollapsed = false
      }
      .font(.caption)
      .accessibilityLabel("Expand histogram")
      .accessibilityHint("Expands the histogram to jump to a time")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 6)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Histogram collapsed: \(summaryText), Expand to jump")
  }

  private var summaryText: String {
    let entries = filteredRows.count
    let errors = filteredRows.count(where: { $0.level == "error" })
    let warnings = filteredRows.count(where: { $0.level == "warning" })
    let span = spanText
    return "\(entries) entries · \(errors) errors · \(warnings) warnings · \(span) · \(launchCount) launches"
  }

  private var spanText: String {
    guard
      let earliest = buckets.first?.startMilliseconds,
      let latest = buckets.last?.endMilliseconds
    else {
      return "no span"
    }
    return "\(LogExport.displayTime(milliseconds: earliest).prefix(5)) – \(LogExport.displayTime(milliseconds: latest).prefix(5))"
  }

  private var sparkline: some View {
    HStack(alignment: .bottom, spacing: 1) {
      ForEach(buckets.indices, id: \.self) { index in
        let bucket = buckets[index]
        RoundedRectangle(cornerRadius: 1)
          .fill(barColor(for: bucket))
          .opacity(bucket.filteredCount == 0 ? 0.25 : 1)
          .frame(width: 3, height: barHeight(for: bucket, maxHeight: 14))
          .overlay {
            if bucket.holdsSelection {
              RoundedRectangle(cornerRadius: 1)
                .stroke(.blue, lineWidth: 1)
            }
          }
      }
    }
    .frame(height: 14)
    .accessibilityHidden(true)
  }

  private var axisRow: some View {
    HStack {
      ForEach(axisTicks, id: \.self) { tick in
        Text(tick)
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(.secondary)
        if tick != axisTicks.last {
          Spacer()
        }
      }
    }
    .padding(.horizontal, 40)
    .accessibilityHidden(true)
  }

  private var axisTicks: [String] {
    guard let first = buckets.first, let last = buckets.last else {
      return []
    }
    let mid = (first.startMilliseconds + last.endMilliseconds) / 2
    return [
      String(LogExport.displayTime(milliseconds: first.startMilliseconds).prefix(5)),
      String(LogExport.displayTime(milliseconds: mid).prefix(5)),
      String(LogExport.displayTime(milliseconds: last.endMilliseconds).prefix(5)),
    ]
  }

  @ViewBuilder
  private var hoverHint: some View {
    if let hoveredIndex, buckets.indices.contains(hoveredIndex) {
      let bucket = buckets[hoveredIndex]
      HStack(spacing: 6) {
        Text("Jump to \(LogExport.displayTime(milliseconds: bucket.startMilliseconds))")
          .font(.caption)
        Text("Right-click for Jump to Time…")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .accessibilityLabel("Jump to \(LogExport.displayTime(milliseconds: bucket.startMilliseconds))")
    }
  }

  private var collapseButton: some View {
    Button {
      isCollapsed.toggle()
    } label: {
      Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
        .font(.caption)
    }
    .buttonStyle(.plain)
    .frame(width: 20, height: 20)
    .accessibilityLabel(isCollapsed ? "Expand histogram" : "Collapse histogram")
  }

  private func barsRow(height: CGFloat) -> some View {
    HStack(alignment: .bottom, spacing: 1) {
      ForEach(buckets.indices, id: \.self) { index in
        let bucket = buckets[index]
        RoundedRectangle(cornerRadius: 2)
          .fill(barColor(for: bucket))
          .opacity(barOpacity(for: bucket))
          .frame(maxWidth: .infinity, minHeight: 2, maxHeight: .infinity)
          .frame(height: barHeight(for: bucket, maxHeight: height))
          .overlay {
            if bucket.holdsSelection {
              RoundedRectangle(cornerRadius: 2)
                .stroke(Color.accentColor, lineWidth: 2)
            }
          }
          .onHover { hovering in
            hoveredIndex = hovering ? index : nil
          }
          .contextMenu {
            Button("Jump to \(LogExport.displayTime(milliseconds: bucket.startMilliseconds))") {
              onJumpToMilliseconds(bucket.startMilliseconds)
            }
            Button("Jump to Time…") {
              onOpenJumpDialog()
            }
            .keyboardShortcut("j", modifiers: .command)
            Divider()
            Button("Show Only This Interval") {
              onShowInterval(bucket.startMilliseconds, bucket.endMilliseconds)
            }
            Button("Show Only This Launch") {
              if let launch = launchNear(milliseconds: bucket.startMilliseconds) {
                onShowLaunch(launch)
              }
            }
            Button("Reset Time Range") {
              onResetTime()
            }
            Divider()
            Button("Copy Entries in This Interval") {
              onCopyInterval(bucket.startMilliseconds, bucket.endMilliseconds)
            }
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(
            "\(LogExport.displayTime(milliseconds: bucket.startMilliseconds)) – \(LogExport.displayTime(milliseconds: bucket.endMilliseconds)) · \(bucket.filteredCount) entries"
          )
      }
    }
    .frame(height: height)
  }

  private func barColor(for bucket: HistogramBucket) -> Color {
    if bucket.errorCount > 0 {
      return .red
    }
    if bucket.warningCount > 0 {
      return .orange
    }
    if bucket.filteredCount < bucket.totalCount {
      return .blue.opacity(0.5)
    }
    return .blue
  }

  private func barOpacity(for bucket: HistogramBucket) -> Double {
    if bucket.totalCount == 0 {
      return 0.15
    }
    if bucket.filteredCount == 0 {
      return 0.2
    }
    if bucket.filteredCount < bucket.totalCount {
      return 0.55
    }
    return 1
  }

  private func barHeight(for bucket: HistogramBucket, maxHeight: CGFloat) -> CGFloat {
    let peak = buckets.map(\.totalCount).max() ?? 1
    guard peak > 0 else {
      return 2
    }
    let ratio = Double(max(bucket.filteredCount, bucket.totalCount > 0 && bucket.filteredCount == 0 ? 1 : 0)) / Double(peak)
    return max(2, maxHeight * CGFloat(ratio))
  }

  private func launchNear(milliseconds: Int64) -> String? {
    let near = (filteredRows + totalRows).min { first, second in
      abs(first.recordedAtMilliseconds - milliseconds) < abs(second.recordedAtMilliseconds - milliseconds)
    }
    return near?.launchID
  }

}
