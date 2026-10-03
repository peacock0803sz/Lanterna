import Foundation

/// Holds a press the show delay is keeping off the screen, until the wait
/// is over and there is a list to show it with.
///
/// Beside `PendingPressHold`, which waits on the first list alone, so each
/// wait answers its own question: that one whether there is anything to
/// show yet, this one whether showing it is still wanted. A press the delay
/// is holding can be added to by further presses, which that one turns away.
@MainActor
final class PendingShowHold {

  // MARK: Lifecycle

  init(
    sleep: @escaping @MainActor (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    },
    fire: @escaping @MainActor (PendingShow) -> Void
  ) {
    self.sleep = sleep
    self.fire = fire
  }

  // MARK: Internal

  /// A press the delay is holding: the presses in arrival order, the
  /// instant the first of them arrived, and the list once it arrives.
  struct PendingShow {
    var presses: [HotkeyCombination]
    var startedAt: ContinuousClock.Instant
    var items: [WindowItem]?
    /// Whether the wait has run out. Firing needs this and a list.
    var delayElapsed = false
    /// Whether the list was gathered for this wait. Read off the
    /// measurement the firing writes.
    var gatheredOnDemand = false
  }

  /// Whether a press is waiting, which is to say whether showing is still
  /// an open question.
  var isWaiting: Bool {
    pending != nil
  }

  /// Takes a press into the hold, or adds it to the one already there.
  ///
  /// Either way the wait starts over: a burst of presses opens one panel
  /// when the burst ends rather than one per press. The measured start
  /// stays where the first press put it, so hurrying does not shorten
  /// the figure by restarting it.
  func begin(
    _ combination: HotkeyCombination,
    startedAt: ContinuousClock.Instant,
    delay: Duration
  ) {
    if pending == nil {
      pending = PendingShow(
        presses: [combination],
        startedAt: startedAt,
        items: nil
      )
    } else {
      pending?.presses.append(combination)
      pending?.delayElapsed = false
    }
    generation += 1
    let seen = generation
    timer?.cancel()
    timer = Task { [weak self] in
      await self?.sleep(delay)
      guard let self, generation == seen else { return }
      timer = nil
      pending?.delayElapsed = true
      fireIfReady()
    }
  }

  /// Hands the hold the list it was waiting on. Fires when the wait has
  /// already run out; otherwise the firing stays owed to the timer.
  func listArrived(_ items: [WindowItem], gatheredOnDemand: Bool = false) {
    guard pending != nil else { return }
    pending?.items = items
    pending?.gatheredOnDemand = gatheredOnDemand
    fireIfReady()
  }

  /// Takes the waiting press off the hold, so a release can answer it.
  ///
  /// Cancelling the timer is what stops the firing: whatever the timer
  /// was owed dies with the wait it belonged to.
  func take() -> PendingShow? {
    timer?.cancel()
    timer = nil
    defer { pending = nil }
    return pending
  }

  /// Gives up on the press that was waiting, so nothing appears for it.
  func callOff() {
    timer?.cancel()
    timer = nil
    pending = nil
  }

  // MARK: Private

  /// The press that is waiting, if one is.
  private var pending: PendingShow?

  /// The wait now running, if one is. One wait for one hold: a press
  /// added to the hold replaces the wait rather than joining it, and the
  /// count below tells a replaced wait from the one that replaced it.
  private var timer: Task<Void, Never>?

  /// Tells a replaced wait from its replacement. The sleep cannot be
  /// trusted to throw on cancellation — a test double may simply return —
  /// so the wait that wakes checks it is still the wait that was asked.
  private var generation = 0

  /// Waits out one delay. Injected so a test need not wait a real one out.
  private let sleep: @MainActor (Duration) async -> Void

  /// Puts the panel up for the press that waited out its delay.
  private let fire: @MainActor (PendingShow) -> Void

  /// Fires when the wait has run out on a press with a list. Anything
  /// else stays waiting: a wait with no list yet, or a list whose wait
  /// was started over.
  private func fireIfReady() {
    guard let waiting = pending, waiting.delayElapsed, waiting.items != nil else {
      return
    }
    pending = nil
    timer = nil
    fire(waiting)
  }

}
