import Foundation

// MARK: - PanelRows

/// How many rows the panel shows before the list scrolls.
///
/// The configuration file spells the count and the settings stepper
/// steps it, so both meet here instead of each keeping its own range.
/// A count outside the range is not a smaller or larger limit but a bad
/// value, and the caller falls back instead of guessing.
struct PanelRows: Equatable, Sendable {

  // MARK: Lifecycle

  /// The limit a count spells, when the count is in range.
  init?(count: Int) {
    guard Self.range.contains(count) else { return nil }
    self.count = count
  }

  private init(uncheckedCount count: Int) {
    self.count = count
  }

  // MARK: Internal

  /// The counts a limit may take. Five keeps the list readable. The top
  /// is past what most displays hold at the standard text size, and the
  /// display fit cuts the panel short of a count the display cannot show.
  static let range = 5 ... 60

  /// The limit when nothing is spelled.
  static let standard = PanelRows(uncheckedCount: 10)

  let count: Int

}

extension PanelRows {
  /// The limit one run uses: a spelled count wins, anything missing
  /// means the standard limit.
  static func effective(from config: ValidConfiguration) -> PanelRows {
    config.panelRows.flatMap(PanelRows.init(count:)) ?? .standard
  }
}
