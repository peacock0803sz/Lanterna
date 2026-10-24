/// The commit switches a commit hands to the switcher, read fresh at each
/// take.
///
/// They default off, so a commit that never sets them takes the default
/// path with no notes. Held as one value rather than
/// loose flags so the commit path reads and hands over the switches
/// together; nothing here is per switcher, because the commit switches
/// apply the same whichever switcher took the row.
struct ActivationPolicy: Equatable, Sendable {
  /// The commit switches off: the default path, with no notes.
  static let off = ActivationPolicy(reopensWindowlessApps: false, raisesOnlyChosenWindow: false)

  /// Opens a window when the taken row names an application with none,
  /// the way that application's Dock icon does.
  var reopensWindowlessApps: Bool
  /// Brings only the taken window forward, trying to leave the
  /// application's other windows where they were on every display.
  var raisesOnlyChosenWindow: Bool
}
