import AppKit

// MARK: - AssignmentNote

/// What the note under one group assignment row says.
enum AssignmentNote: Equatable, Sendable {
  /// Nothing typed yet.
  case blank
  /// An installed application that is running.
  case found(name: String, bundleIdentifier: String)
  /// An installed application that is not running.
  case notRunning(name: String)
  /// No installed application has this identifier.
  case missing
  /// An earlier row already assigns this application; saving keeps that one.
  case alreadyAssigned

  // MARK: Internal

  var text: String {
    switch self {
    case .blank: ""
    case .found(let name, let bundleIdentifier): "\(name) · \(bundleIdentifier)"
    case .notRunning(let name): "\(name) · not running"
    case .missing: "No app found for this bundle ID"
    case .alreadyAssigned: "Already assigned"
    }
  }

  /// Whether the note points at something the row will not do as written.
  var isProblem: Bool {
    self == .missing || self == .alreadyAssigned
  }
}

// MARK: - AssignmentAppResolver

/// How a group assignment row finds the application it names, for display
/// only. The text is looked up as an installed application's bundle
/// identifier and nothing else: unlike an exclusion, an assignment never
/// names applications by pattern.
@MainActor
enum AssignmentAppResolver {

  // MARK: Internal

  /// The note for one row, given the rows above it.
  static func note(
    for bundleID: String,
    earlier: [GroupAssignment],
    installed: @MainActor (String) -> ResolvedExclusionApp? = ExclusionAppResolver.installedApp,
    isRunning: @MainActor (String) -> Bool = Self.isRunning
  ) -> AssignmentNote {
    let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .blank }
    let folded = trimmed.lowercased()
    if earlier.contains(where: { $0.bundleID.trimmingCharacters(in: .whitespaces).lowercased() == folded }) {
      return .alreadyAssigned
    }
    guard let app = installed(trimmed) else { return .missing }
    return isRunning(trimmed) ? .found(name: app.name, bundleIdentifier: app.bundleIdentifier) : .notRunning(name: app.name)
  }

  // MARK: Private

  private static func isRunning(_ bundleID: String) -> Bool {
    let folded = bundleID.lowercased()
    return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier?.lowercased() == folded }
  }

}
