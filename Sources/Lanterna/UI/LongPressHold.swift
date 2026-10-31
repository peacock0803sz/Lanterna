import AppKit

// MARK: - LongPressHold

/// Holds a press that is both a letter and a window action, until it shows
/// which one it is.
///
/// With typing starting the filter, Command-W could mean the letter w or
/// closing the window. Held past the system's own delay before a key
/// repeats, it is the action; let go sooner, or followed by another key, it
/// is the letter. Reading the system's delay keeps the line where the user
/// already set it for every other held key.
@MainActor
final class LongPressHold {

  // MARK: Lifecycle

  /// The delay and the waiting are closures so a test can stand in for the
  /// system setting and the clock.
  init(
    threshold: @escaping @MainActor () -> Duration = { .seconds(NSEvent.keyRepeatDelay) },
    sleep: @escaping @MainActor (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    }
  ) {
    self.threshold = threshold
    self.sleep = sleep
  }

  // MARK: Internal

  /// The press being held, if any.
  private(set) var pending: PanelKeystroke?

  /// Starts holding a press. `onHeld` runs once the delay passes with the
  /// press still held; anything that ends the wait first means it never runs.
  func begin(_ keystroke: PanelKeystroke, onHeld: @escaping @MainActor () -> Void) {
    cancel()
    pending = keystroke
    // Read as the key goes down, so a setting changed mid-hold does not
    // move a wait already under way.
    let delay = threshold()
    let sleep = sleep
    task = Task { [weak self] in
      await sleep(delay)
      guard !Task.isCancelled, self?.pending != nil else { return }
      onHeld()
    }
  }

  /// Ends the wait and hands back the press, for whoever reads it as a letter.
  func take() -> PanelKeystroke? {
    defer { cancel() }
    return pending
  }

  /// Ends the wait and forgets the press.
  func cancel() {
    task?.cancel()
    task = nil
    pending = nil
  }

  // MARK: Private

  private let threshold: @MainActor () -> Duration
  private let sleep: @MainActor (Duration) async -> Void
  private var task: Task<Void, Never>?

}
