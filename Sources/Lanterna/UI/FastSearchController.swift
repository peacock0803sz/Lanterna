import Logging

// MARK: - FastSearchController

/// Owns the Fast Search tap and connects it to the presenter.
///
/// Makes the tap while any modifier is enabled and takes it down when none
/// is, keeps the tap's copy of the conditions current, and hands what the
/// tap reports to the presenter: a search that started, its later keys,
/// and the release. Says once why Fast Search cannot run, and again only
/// when the reason changes.
@MainActor
final class FastSearchController {

  // MARK: Lifecycle

  init(
    tap: any FastSearchTapControlling = SystemFastSearchTap(),
    tables: KeyCharacterTableWatch = KeyCharacterTableWatch(),
    capture: KeyCaptureActivity = .shared,
    now: @escaping @MainActor () -> ContinuousClock.Instant = { .now },
    healthCheckInterval: Duration = .seconds(2),
    writeLine: @escaping @MainActor (LogLine) -> Void = { line in
      guard Diagnostics.logger != nil else { return }
      Diagnostics.writeLine(line)
    }
  ) {
    self.tap = tap
    self.tables = tables
    self.capture = capture
    self.now = now
    self.healthCheckInterval = healthCheckInterval
    self.writeLine = writeLine
  }

  // MARK: Internal

  /// What the tap's thread decides with. Shared rather than copied.
  let box = FastSearchGateBox()

  /// Whether a tap is up.
  private(set) var isRunning = false

  /// The presenter that shows searches. Wires its notices back here.
  weak var presenter: PanelPresenter? {
    didSet {
      presenter?.onSwitcherSessionChanged = { [weak self] in self?.pushCanStart() }
      presenter?.onFastSearchClosed = { [weak self] in self?.box.panelClosed() }
      pushCanStart()
    }
  }

  /// Takes the enabled modifiers, at launch and on every settings change.
  func apply(modifiers: Set<FastSearchModifier>) {
    box.updateConditions { $0.enabled = modifiers }
    guard !modifiers.isEmpty else {
      guard isRunning else { return }
      stopTap()
      writeLine(LogLine(.info, .hotkey, "fast search tap removed; no modifier is enabled"))
      return
    }
    if isRunning {
      return
    }
    startTap(modifiers)
  }

  /// Takes the tap down for good, at quit.
  func shutdown() {
    stopTap()
  }

  /// Asks the tap whether it is still up, and puts it back if not.
  func checkHealth() {
    guard isRunning else { return }
    let checkedAt = now()
    guard !tap.isEnabled else {
      lastKnownEnabledAt = checkedAt
      return
    }
    let downFor = checkedAt - lastKnownEnabledAt
    guard tap.enable() else {
      writeLine(LogLine(.error, .hotkey, "fast search tap was found disabled; could not re-enable it"))
      return
    }
    lastKnownEnabledAt = checkedAt
    writeLine(LogLine(
      .warning,
      .hotkey,
      "fast search tap was found disabled; re-enabled \(Diagnostics.millisecondsText(downFor)) ms after it went down"
    ))
  }

  /// Hands one report from the tap to the presenter.
  func handle(_ effect: FastSearchEffect) {
    switch effect {
    case .begin(let keystroke, let modifier, let receivedAt, let deliveryDelay):
      begin(keystroke, modifier: modifier, receivedAt: receivedAt, deliveryDelay: deliveryDelay)

    case .keystroke(let keystroke):
      guard let presenter, presenter.fastSearchSession != nil else { return }
      presenter.fastSearchKeystroke(keystroke)

    case .move(let move):
      guard let presenter, presenter.fastSearchSession != nil else { return }
      presenter.fastSearchMove(move)

    case .release(_, let receivedAt):
      guard let presenter, presenter.fastSearchSession != nil else { return }
      presenter.fastSearchRelease(receivedAt: receivedAt)

    case .interrupted:
      guard let presenter, presenter.fastSearchSession != nil else { return }
      presenter.fastSearchInterrupted()
    }
  }

  // MARK: Private

  private let tap: any FastSearchTapControlling
  private let tables: KeyCharacterTableWatch
  private let capture: KeyCaptureActivity
  private let now: @MainActor () -> ContinuousClock.Instant
  private let healthCheckInterval: Duration
  private let writeLine: @MainActor (LogLine) -> Void

  private var healthCheckTask: Task<Void, Never>?
  private var lastKnownEnabledAt = ContinuousClock.now
  /// The last reason given for having no tap, so it is not repeated.
  private var lastUnavailableReason: String?

  private func startTap(_ modifiers: Set<FastSearchModifier>) {
    box.reset()
    tables.start { [weak self] table in
      self?.box.updateConditions { $0.characters = table }
    }
    capture.onChange = { [weak self] _ in self?.pushCanStart() }
    pushCanStart()
    let started = tap.start(
      box: box,
      onEffect: { [weak self] effect in self?.handle(effect) },
      onDisabledBySystem: { [weak self] reenabled in self?.noteDisabledBySystem(reenabled: reenabled) }
    )
    guard started else {
      tables.stop()
      let reason = "fast search is unavailable; the keyboard tap could not be created "
        + "(accessibility granted: \(tap.accessibilityGranted ? "yes" : "no"))"
      if reason != lastUnavailableReason {
        writeLine(LogLine(.warning, .hotkey, reason))
        lastUnavailableReason = reason
      }
      return
    }
    lastUnavailableReason = nil
    isRunning = true
    lastKnownEnabledAt = now()
    let names = FastSearchModifier.allCases.filter(modifiers.contains).map(\.displayName)
    writeLine(LogLine(.info, .hotkey, "fast search tap started for \(names.joined(separator: ", "))"))
    startHealthChecks()
  }

  private func stopTap() {
    healthCheckTask?.cancel()
    healthCheckTask = nil
    tap.stop()
    tables.stop()
    isRunning = false
  }

  /// Copies whether a search may start now to the tap's thread.
  private func pushCanStart() {
    let canStart = !(presenter?.hasSwitcherSession ?? true) && !capture.isCapturing
    box.updateConditions { $0.canStart = canStart }
  }

  private func begin(
    _ keystroke: PanelKeystroke,
    modifier: FastSearchModifier,
    receivedAt: ContinuousClock.Instant,
    deliveryDelay: Duration?
  ) {
    // A letter that got past the tap before the conditions caught up: the
    // recording or the panel takes it, and the search stands down.
    guard let presenter, !capture.isCapturing else {
      box.standDown()
      return
    }
    let started = presenter.beginFastSearch(
      keystroke,
      modifier: modifier,
      receivedAt: receivedAt,
      deliveryDelay: deliveryDelay,
      gateIsRunning: { [box] in box.isRunning }
    )
    if started != .started {
      box.standDown()
    }
  }

  private func noteDisabledBySystem(reenabled: Bool) {
    if reenabled {
      lastKnownEnabledAt = now()
      writeLine(LogLine(.warning, .hotkey, "fast search tap was disabled by the system; re-enabled"))
    } else {
      writeLine(LogLine(.error, .hotkey, "fast search tap was disabled by the system; could not re-enable it"))
    }
  }

  private func startHealthChecks() {
    healthCheckTask?.cancel()
    healthCheckTask = Task { [weak self, healthCheckInterval] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: healthCheckInterval)
        } catch {
          return
        }
        guard !Task.isCancelled, let self else { return }
        checkHealth()
      }
    }
  }

}
