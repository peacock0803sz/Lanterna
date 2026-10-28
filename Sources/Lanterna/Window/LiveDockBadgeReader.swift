import AppKit
import ApplicationServices

// MARK: - RunningDockApplication

/// A running application as far as matching it to a Dock tile goes.
struct RunningDockApplication: Equatable {
  let processIdentifier: pid_t
  let bundleURL: URL?
  /// Whether it is an ordinary application. Only those get a Dock tile.
  let isRegular: Bool
}

// MARK: - LiveDockBadgeReader

/// Reads the badges off the Dock's application tiles over the
/// accessibility API, and matches each tile to the process it stands for.
///
/// Runs on the main thread while the panel is going up, so every call is
/// bounded by what is left of the deadline. Messaging timeouts belong to
/// one element each and a child does not inherit its parent's, so each
/// element is given the time left right before it is asked; one left out
/// would wait on the multi-second default.
struct LiveDockBadgeReader: DockBadgeReading {

  // MARK: Lifecycle

  /// The defaults talk to the real Dock. Tests replace them, because no
  /// real Dock can be made to fail or stall on cue.
  init(
    dockProcessIdentifier: @escaping @MainActor () -> pid_t? = {
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    },
    setMessagingTimeout: @escaping @MainActor (AXUIElement, Float) -> AXError = {
      AXUIElementSetMessagingTimeout($0, $1)
    },
    copyChildren: @escaping @MainActor (AXUIElement) -> (AXError, [AXUIElement]) = { element in
      var value: CFTypeRef?
      let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
      return (error, value as? [AXUIElement] ?? [])
    },
    copyRole: @escaping @MainActor (AXUIElement) -> (AXError, String?) = { element in
      var value: CFTypeRef?
      let error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
      return (error, value as? String)
    },
    copyTileAttributes: @escaping @MainActor (AXUIElement) -> (AXError, [Any]) = { element in
      var values: CFArray?
      let error = AXUIElementCopyMultipleAttributeValues(
        element,
        Self.tileAttributes,
        AXCopyMultipleAttributeOptions(rawValue: 0),
        &values
      )
      return (error, values as? [Any] ?? [])
    },
    runningApplications: @escaping @MainActor () -> [RunningDockApplication] = {
      NSWorkspace.shared.runningApplications.map {
        RunningDockApplication(
          processIdentifier: $0.processIdentifier,
          bundleURL: $0.bundleURL,
          isRegular: $0.activationPolicy == .regular
        )
      }
    },
    now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }
  ) {
    self.dockProcessIdentifier = dockProcessIdentifier
    self.setMessagingTimeout = setMessagingTimeout
    self.copyChildren = copyChildren
    self.copyRole = copyRole
    self.copyTileAttributes = copyTileAttributes
    self.runningApplications = runningApplications
    self.now = now
  }

  // MARK: Internal

  func read(deadline: Duration) -> BadgeReading {
    let started = now()
    let clock = Clock(started: started, deadline: deadline, now: now)
    let outcome: BadgeReading.Outcome
    var badges = AppBadges.none
    do throws(Stop) {
      badges = try readTiles(clock)
      outcome = .read
    } catch {
      outcome = error.outcome
    }
    return BadgeReading(badges: badges, outcome: outcome, elapsed: now() - started)
  }

  // MARK: Private

  /// Why a read ended early.
  private struct Stop: Error {
    let outcome: BadgeReading.Outcome
  }

  /// The time a read has, measured from when it started.
  private struct Clock {
    let started: ContinuousClock.Instant
    let deadline: Duration
    let now: @MainActor () -> ContinuousClock.Instant

    @MainActor
    var elapsed: Duration {
      now() - started
    }
  }

  /// A tile that carries a badge, before it is matched to a process.
  private struct BadgedTile {
    let url: URL
    let badge: AppBadge
  }

  /// Subrole first, to tell application tiles from folders and the
  /// trash; then where the application lives and what its badge says.
  private static let tileAttributes = ["AXSubrole", "AXURL", "AXStatusLabel"] as CFArray

  /// Answers a timeout can return a hair before it is due: the clock it
  /// keeps is not ours.
  private static let lateSlack = Duration.milliseconds(2)

  /// A tile answered in a shape the Dock never uses.
  private static let unexpectedTileAnswer = Stop(outcome: .failed(reason: "unexpectedTileAnswer"))

  private let dockProcessIdentifier: @MainActor () -> pid_t?
  private let setMessagingTimeout: @MainActor (AXUIElement, Float) -> AXError
  private let copyChildren: @MainActor (AXUIElement) -> (AXError, [AXUIElement])
  private let copyRole: @MainActor (AXUIElement) -> (AXError, String?)
  private let copyTileAttributes: @MainActor (AXUIElement) -> (AXError, [Any])
  private let runningApplications: @MainActor () -> [RunningDockApplication]
  private let now: @MainActor () -> ContinuousClock.Instant

  /// The path a tile and a running application are compared by, with any
  /// trailing slash dropped, so one bundle compares equal however each
  /// side ends it. Links are left alone: resolving them would ask the
  /// filesystem on the main thread.
  private static func comparablePath(_ url: URL) -> String {
    var path = url.standardizedFileURL.path
    while path.count > 1, path.hasSuffix("/") {
      path.removeLast()
    }
    return path
  }

  /// The error a per-attribute answer carries, when it is one.
  private static func attributeError(_ value: Any) -> AXError? {
    let reference = value as CFTypeRef
    guard CFGetTypeID(reference) == AXValueGetTypeID() else {
      return nil
    }
    let axValue = unsafeDowncast(reference, to: AXValue.self)
    var error = AXError.success
    guard AXValueGetType(axValue) == .axError, AXValueGetValue(axValue, .axError, &error) else {
      return nil
    }
    return error
  }

  /// One value out of a tile's answer, or nil when the tile has none.
  ///
  /// A tile with no badge answers that its label has no value, and a tile
  /// may lack an attribute altogether, answering that there is no such
  /// attribute; both mean the value is absent. Any other error, or a value
  /// of a type the Dock never answers with, fails the read rather than
  /// passing for a tile without a badge.
  private static func attribute<Value>(_ value: Any, as _: Value.Type) throws(Stop) -> Value? {
    if let error = attributeError(value) {
      guard error == .noValue || error == .attributeUnsupported else {
        throw failure(error)
      }
      return nil
    }
    guard let typed = value as? Value else {
      throw unexpectedTileAnswer
    }
    return typed
  }

  private static func failure(_ error: AXError) -> Stop {
    Stop(outcome: .failed(reason: "error \(error.rawValue)"))
  }

  private func readTiles(_ clock: Clock) throws(Stop) -> AppBadges {
    guard let dockPID = dockProcessIdentifier() else {
      throw Stop(outcome: .noDock)
    }
    let application = AXUIElementCreateApplication(dockPID)
    var list: AXUIElement?
    for child in try ask(application, clock, copyChildren) {
      if try ask(child, clock, copyRole) == "AXList" {
        list = child
        break
      }
    }
    guard let list else {
      throw Stop(outcome: .failed(reason: "noDockList"))
    }
    var badged = [BadgedTile]()
    for tile in try ask(list, clock, copyChildren) {
      if let found = try badgedTile(tile, clock) {
        badged.append(found)
      }
    }
    try checkTime(clock)
    let badges = match(badged)
    try checkTime(clock)
    return badges
  }

  /// One tile's badge, or nil for a tile that is not an application or
  /// shows none.
  private func badgedTile(_ tile: AXUIElement, _ clock: Clock) throws(Stop) -> BadgedTile? {
    let values = try ask(tile, clock, copyTileAttributes)
    guard values.count == 3 else {
      throw Self.unexpectedTileAnswer
    }
    guard try Self.attribute(values[0], as: String.self) == "AXApplicationDockItem" else {
      return nil
    }
    let url = try Self.attribute(values[1], as: URL.self)
    let label = try Self.attribute(values[2], as: String.self)
    guard let url, let badge = AppBadge(statusLabel: label) else {
      return nil
    }
    return BadgedTile(url: url, badge: badge)
  }

  /// Gives each badge to the one ordinary process launched from its
  /// tile's bundle. Copies launched from one place share a tile address,
  /// and nothing on a tile says which copy it is, so those get none.
  private func match(_ badged: [BadgedTile]) -> AppBadges {
    guard !badged.isEmpty else {
      return .none
    }
    var processes = [String: [pid_t]]()
    for application in runningApplications() where application.isRegular {
      if let url = application.bundleURL {
        processes[Self.comparablePath(url), default: []].append(application.processIdentifier)
      }
    }
    var byProcess = [pid_t: AppBadge]()
    for tile in badged {
      if let owners = processes[Self.comparablePath(tile.url)], owners.count == 1 {
        byProcess[owners[0]] = tile.badge
      }
    }
    return AppBadges(byProcess: byProcess)
  }

  private func checkTime(_ clock: Clock) throws(Stop) {
    if clock.elapsed >= clock.deadline {
      throw Stop(outcome: .late)
    }
  }

  /// Makes one call to one element, with that element's timeout set to
  /// the time left. A timeout that runs out at the deadline is lateness,
  /// not a fault in the Dock.
  private func ask<Value>(
    _ element: AXUIElement,
    _ clock: Clock,
    _ call: @MainActor (AXUIElement) -> (AXError, Value)
  ) throws(Stop) -> Value {
    let left = clock.deadline - clock.elapsed
    guard left > .zero else {
      throw Stop(outcome: .late)
    }
    let seconds = Double(left.components.seconds) + Double(left.components.attoseconds) * 1e-18
    let timeoutError = setMessagingTimeout(element, Float(seconds))
    guard timeoutError == .success else {
      throw Self.failure(timeoutError)
    }
    let (error, value) = call(element)
    guard error == .success else {
      if error == .cannotComplete, clock.elapsed >= clock.deadline - Self.lateSlack {
        throw Stop(outcome: .late)
      }
      throw Self.failure(error)
    }
    return value
  }

}
