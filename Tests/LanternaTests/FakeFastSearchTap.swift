@testable import Lanterna

// MARK: - FakeFastSearchTap

/// A Fast Search tap that records what it was asked and lets a test speak
/// for it.
@MainActor
final class FakeFastSearchTap: FastSearchTapControlling {

  // MARK: Internal

  var accessibilityGranted = true
  /// Whether the next `start` succeeds.
  var startSucceeds = true
  /// Whether `enable` succeeds.
  var enableSucceeds = true

  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var enableCount = 0
  private(set) var isEnabled = false
  private(set) var box: FastSearchGateBox?

  func start(
    box: FastSearchGateBox,
    onEffect: @escaping @MainActor (FastSearchEffect) -> Void,
    onDisabledBySystem: @escaping @MainActor (_ reenabled: Bool) -> Void
  ) -> Bool {
    startCount += 1
    guard startSucceeds else { return false }
    self.box = box
    self.onEffect = onEffect
    self.onDisabledBySystem = onDisabledBySystem
    isEnabled = true
    return true
  }

  func enable() -> Bool {
    enableCount += 1
    isEnabled = enableSucceeds
    return enableSucceeds
  }

  func stop() {
    stopCount += 1
    isEnabled = false
    onEffect = nil
    onDisabledBySystem = nil
  }

  /// Reports an effect the way the tap's thread would.
  func send(_ effect: FastSearchEffect) {
    onEffect?(effect)
  }

  /// Goes down without saying so, for the health check to find.
  func goDownSilently() {
    isEnabled = false
  }

  /// Says the system stopped the tap.
  func reportDisabled(reenabled: Bool) {
    onDisabledBySystem?(reenabled)
  }

  // MARK: Private

  private var onEffect: (@MainActor (FastSearchEffect) -> Void)?
  private var onDisabledBySystem: (@MainActor (Bool) -> Void)?

}
