import Darwin

// MARK: - WindowScope

/// Which applications' rows the switcher lists.
///
/// Mirrors the config file values (`"allApps"`, `"frontApp"`).
enum WindowScope: String, Sendable {
  case allApps
  /// Only the application that was in front when the panel opened.
  case frontApp

  // MARK: Internal

  /// The other scope, for the key that switches between them.
  var toggled: WindowScope {
    self == .allApps ? .frontApp : .allApps
  }
}

// MARK: - ScopeState

/// The scope one appearance lists.
///
/// The configured scope is where every appearance starts; the panel key
/// changes only the current one, so closing the panel puts the setting
/// back. The target is read once as the panel opens: the panel never
/// becomes the active application, so what was in front stays in front
/// while it is up.
struct ScopeState: Equatable, Sendable {

  var configured = WindowScope.allApps
  private(set) var current = WindowScope.allApps
  private(set) var target: pid_t?

  /// The owner whose rows stay, or nil when every row stays. With no
  /// known target nothing is narrowed: missing information never hides.
  var narrowedOwner: pid_t? {
    current == .frontApp ? target : nil
  }

  /// Starts an appearance on the configured scope over this target.
  mutating func begin(target: pid_t?) {
    current = configured
    self.target = target
  }

  /// Switches this appearance to the other scope.
  mutating func toggle() {
    current = current.toggled
  }

}

// MARK: - ScopeBand

/// What the band over a narrowed list says: whose rows these are, and the
/// key that brings every application back.
struct ScopeBand: Equatable, Sendable {
  let appName: String
  let toggleKey: String?
}
