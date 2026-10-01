import SwiftUI

/// The counts under the table, and what ⌘C will copy.
struct LogStatusBar: View {

  // MARK: Internal

  let totalCount: Int
  let shownCount: Int
  let selectedCount: Int
  let isFiltered: Bool
  let isLoading: Bool

  var body: some View {
    HStack(spacing: 6) {
      if isLoading {
        ProgressView()
          .controlSize(.mini)
          .accessibilityHidden(true)
      }
      Text(summary)
      Text("· ⌘C copies selected rows, or every shown row when none is selected")
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .truncationMode(.tail)
        .accessibilityHidden(true)
      Spacer(minLength: 0)
    }
    .font(.system(size: 11))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 14)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.bar)
    .accessibilityElement(children: .combine)
  }

  /// The counts as one line, in the contract's wording.
  static func summary(
    totalCount: Int,
    shownCount: Int,
    selectedCount: Int,
    isFiltered: Bool,
    isLoading: Bool
  ) -> String {
    if isLoading {
      return "Loading saved logs…"
    }
    let counts =
      if isFiltered {
        "Showing \(shownCount) of \(totalCount) \(entries(totalCount))"
      } else {
        "\(totalCount) \(entries(totalCount))"
      }
    return "\(counts) · \(selectedCount) selected"
  }

  // MARK: Private

  private var summary: String {
    Self.summary(
      totalCount: totalCount,
      shownCount: shownCount,
      selectedCount: selectedCount,
      isFiltered: isFiltered,
      isLoading: isLoading
    )
  }

  private static func entries(_ count: Int) -> String {
    count == 1 ? "entry" : "entries"
  }

}
