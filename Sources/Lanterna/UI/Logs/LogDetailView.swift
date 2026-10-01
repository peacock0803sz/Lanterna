import SwiftUI

// MARK: - LogDetailView

/// Detail pane for one selected row.
///
/// Shows the level badge with the full timestamp and the category,
/// plus the complete message text. The owner shows this view below
/// the list in a resizable split when a single row stays selected,
/// and hides it when the selection clears. Closing through the
/// button or esc only clears the selection, so the list keeps its
/// reading position.
struct LogDetailView: View {

  // MARK: Internal

  var row: DiagnosticRow
  var launchStartMilliseconds: Int64?
  var isCurrentLaunch = false
  var onClose: () -> Void = { }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      head
      messageBox
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Entry Detail")
  }

  // MARK: Private

  private var head: some View {
    HStack(spacing: 10) {
      LogLevelBadge(level: row.level)
      Text(LogExport.fullTime(milliseconds: row.recordedAtMilliseconds))
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .accessibilityLabel("Full time \(LogExport.fullTime(milliseconds: row.recordedAtMilliseconds))")
      Text(row.category ?? "—")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .accessibilityLabel("Category \(row.category ?? "no category")")
      Spacer()
      Button {
        onClose()
      } label: {
        Image(systemName: "xmark")
          .font(.callout)
          .frame(width: 22, height: 22)
          .background(.quaternary.opacity(0.5))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Close detail")
      .accessibilityHint("Clears the row selection and closes the detail")
    }
  }

  private var messageBox: some View {
    Text(row.message)
      .font(.system(.body, design: .monospaced))
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .accessibilityLabel("Full message")
  }

}
