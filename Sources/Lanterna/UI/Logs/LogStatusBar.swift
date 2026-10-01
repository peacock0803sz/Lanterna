import SwiftUI

// MARK: - LogStatusBar

/// Counts and hints under the table.
struct LogStatusBar: View {

  // MARK: Internal

  var visibleCount: Int
  var totalCount: Int
  var launchCount: Int
  var selectedCount: Int
  var timeLabel: String
  var isPaused: Bool
  var isFiltered = false
  var showsDetail = false

  @Binding var autoScroll: Bool

  var body: some View {
    HStack(spacing: 12) {
      Text(statusText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel(statusText)
      Spacer()
      Toggle("Auto-scroll", isOn: $autoScroll)
        .toggleStyle(.checkbox)
        .font(.caption)
        .accessibilityLabel("Auto-scroll")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }

  // MARK: Private

  private var statusText: String {
    let base =
      if isFiltered {
        "Showing \(visibleCount) of \(totalCount) entries"
      } else {
        "\(visibleCount) of \(totalCount) entries (\(timeLabel)) · \(launchCount) launches"
      }
    let selected =
      if selectedCount > 0 {
        " · \(selectedCount) selected"
      } else {
        ""
      }
    let paused =
      if isPaused {
        " · Paused, Auto-scroll \(autoScroll ? "on" : "off")"
      } else {
        ""
      }
    let detail =
      if showsDetail {
        " · esc or × closes the detail · drag the divider to resize"
      } else {
        ""
      }
    return "\(base)\(selected)\(paused)\(detail) · ⌘C copies selected rows"
  }

}
