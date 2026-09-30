import Foundation
import Logging
import ServiceManagement

// MARK: - LaunchItemAction

/// What the launch-time sync wants from the login item.
enum LaunchItemAction: Equatable, Sendable {
  case register
  case unregister
  case none
}

// MARK: - LoginItemControlling

/// The OS side of the login item, behind a seam.
///
/// The live implementation talks to `SMAppService.mainApp`; tests bring
/// a fake, so no test run ever touches the machine's login items.
protocol LoginItemControlling: Sendable {
  var status: SMAppService.Status { get }

  func register() throws
  func unregister() throws
}

// MARK: - LiveLoginItem

/// The login item the app itself runs as.
struct LiveLoginItem: LoginItemControlling {
  var status: SMAppService.Status {
    SMAppService.mainApp.status
  }

  func register() throws {
    try SMAppService.mainApp.register()
  }

  func unregister() throws {
    try SMAppService.mainApp.unregister()
  }
}

// MARK: - LaunchAtLogin

/// The launch-at-login sync.
///
/// The setting always wins over the OS state; a mismatch is repaired by
/// registering or unregistering. Anything the sync reports stays a single
/// diagnostics line, and quiet runs stay silent.
enum LaunchAtLogin {
  /// What the sync reports: the line and the level it carries. Changes
  /// are ordinary news; failures ride along as warnings so they stay
  /// visible under the default threshold.
  struct Report: Equatable, Sendable {
    var line: String
    var level: Logger.Level
  }

  /// The live service when the run has a bundle to register, nil when
  /// it runs as a bare executable with nothing the OS could launch.
  static func liveIfBundled() -> (any LoginItemControlling)? {
    Bundle.main.bundleIdentifier == nil ? nil : LiveLoginItem()
  }

  /// Decides the action from the setting and the OS state.
  ///
  /// A pure function over the two inputs, so every combination stays
  /// countable without touching the machine.
  static func action(desired: Bool, status: SMAppService.Status) -> LaunchItemAction {
    switch status {
    case .enabled:
      desired ? .none : .unregister
    case .requiresApproval:
      desired ? .register : .unregister
    case .notRegistered,
         .notFound:
      desired ? .register : .none
    @unknown default:
      desired ? .register : .none
    }
  }

  /// Applies the setting, returning the diagnostics line.
  ///
  /// Returns nil when nothing changed and nothing failed. A failure
  /// never stops the run; the reason rides along in the line instead.
  static func sync(desired: Bool, service: (any LoginItemControlling)?) -> Report? {
    let state = desired ? "on" : "off"
    guard let service else {
      guard desired else { return nil }
      return Report(
        line: "login item unchanged (not a bundled app) (launch at login is on)",
        level: .warning
      )
    }
    switch action(desired: desired, status: service.status) {
    case .none:
      return nil

    case .register:
      do {
        try service.register()
        return Report(line: "login item registered (launch at login is on)", level: .info)
      } catch {
        let reason = (error as NSError).localizedDescription
        return Report(
          line: "login item unchanged (register failed: \(reason)) (launch at login is \(state))",
          level: .warning
        )
      }

    case .unregister:
      do {
        try service.unregister()
        return Report(line: "login item unregistered (launch at login is off)", level: .info)
      } catch {
        let reason = (error as NSError).localizedDescription
        return Report(
          line: "login item unchanged (unregister failed: \(reason)) (launch at login is \(state))",
          level: .warning
        )
      }
    }
  }
}
