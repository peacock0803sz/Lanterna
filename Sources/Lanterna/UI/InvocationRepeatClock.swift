import Foundation

/// Waits out one hold's initial delay, then its interval, until cancelled.
///
/// Modelled on `PendingShowHold`: the sleep is injected, a generation
/// throws away a wait that a newer hold or a release has already replaced,
/// and the tick itself decides nothing. The presenter looks at the
/// keyboard when the tick fires.
@MainActor
final class InvocationRepeatClock {

  // MARK: Lifecycle

  init(
    sleep: @escaping @MainActor (Duration) async -> Void,
    onTick: @escaping @MainActor () -> Void
  ) {
    self.sleep = sleep
    self.onTick = onTick
  }

  // MARK: Internal

  /// Starts a hold. A hold already waiting is cancelled first, so a new
  /// physical press begins its initial delay over again.
  func arm(after initial: Duration, every interval: Duration) {
    cancel()
    let seen = generation
    let pause = interval
    timer = Task { [weak self] in
      await self?.sleep(initial)
      guard let self, generation == seen, !Task.isCancelled else { return }
      onTick()
      while generation == seen, !Task.isCancelled {
        await sleep(pause)
        guard generation == seen, !Task.isCancelled else { return }
        onTick()
      }
    }
  }

  /// Drops the hold. A tick that has not resumed yet finds the generation
  /// moved and does not fire.
  func cancel() {
    generation &+= 1
    timer?.cancel()
    timer = nil
  }

  // MARK: Private

  private let sleep: @MainActor (Duration) async -> Void
  private let onTick: @MainActor () -> Void
  private var generation: UInt = 0
  private var timer: Task<Void, Never>?

}
