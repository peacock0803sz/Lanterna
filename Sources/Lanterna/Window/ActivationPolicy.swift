/// The two switches a commit hands to the switcher, read fresh at each take.
///
/// Both default off, so a commit that never heard of these takes exactly
/// the path it always took. Held as one value rather than two loose flags
/// so the commit path has a single thing to read and a single thing to
/// hand over; nothing here is per switcher, because the two switches apply
/// the same whichever switcher took the row.
struct ActivationPolicy: Equatable, Sendable {
  /// Both switches off: the path before either existed.
  static let off = ActivationPolicy(reopensWindowlessApps: false, raisesOnlyChosenWindow: false)

  /// Opens a window when the taken row names an application with none,
  /// the way that application's Dock icon does.
  var reopensWindowlessApps: Bool
  /// Brings only the taken window forward, leaving the application's other
  /// windows where they were on every display.
  var raisesOnlyChosenWindow: Bool
}
