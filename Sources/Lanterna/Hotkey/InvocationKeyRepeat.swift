import Foundation

// MARK: - HeldModifiers

/// The modifier keys that matter to an invocation binding.
///
/// A value rather than `NSEvent.ModifierFlags` or `CGEventFlags`, so the
/// decision of which way a hold walks can be asked without AppKit and
/// without a keyboard. The presenter translates the live flags at the edge.
struct HeldModifiers: Equatable, Sendable {
  var shift = false
  var control = false
  var option = false
  var command = false

  /// How many of the four schema modifiers this requires.
  var count: Int {
    (shift ? 1 : 0) + (control ? 1 : 0) + (option ? 1 : 0) + (command ? 1 : 0)
  }

  /// Whether every modifier `required` names is down here.
  ///
  /// A forward binding of Command is held during Shift+Command. The
  /// reverse binding is the one that then wins, because it requires more.
  func contains(_ required: HeldModifiers) -> Bool {
    (!required.shift || shift)
      && (!required.control || control)
      && (!required.option || option)
      && (!required.command || command)
  }
}

// MARK: - InvocationKeyRepeat

/// What a held invocation key should do, given that Carbon will not say.
///
/// `RegisterEventHotKey` delivers `kEventHotKeyPressed` once per physical
/// press. Autorepeat never arrives as another hotkey event, so a hold has
/// to be decided from the key's state and the user's repeat timing. The
/// clock that waits, and the presenter that moves the selection, sit
/// outside this type. Nothing here reads the keyboard.
enum InvocationKeyRepeat {

  /// Which way an invocation walks the list.
  enum Direction: Equatable, Sendable {
    case forward
    case backward
  }

  /// The kind of hotkey that just fired, as far as repeating cares.
  enum Role: Equatable, Sendable {
    case forward
    case backward
    case filter
  }

  /// One invocation key the repeat may follow.
  struct Binding: Equatable, Sendable {
    var keyCode: UInt16
    var modifiers: HeldModifiers
    var direction: Direction
  }

  /// How long to wait before the first repeat, and between the ones after.
  struct Timing: Equatable, Sendable {
    var initialDelay: Duration
    var interval: Duration
  }

  /// One look at a hold that is already armed.
  enum Step: Equatable, Sendable {
    case move(Direction)
    case stop
  }

  /// A navigation press that leaves the panel walking arms a repeat.
  ///
  /// Filter does not walk. A press that is about to dismiss the panel
  /// does not either: there is no selection left to move, and arming one
  /// would fight the close.
  static func shouldArm(role: Role, panelStaysUpWalking: Bool) -> Bool {
    guard panelStaysUpWalking else { return false }
    switch role {
    case .forward,
         .backward:
      return true
    case .filter:
      return false
    }
  }

  /// The direction the keys that are down name, or nothing if they name
  /// none.
  ///
  /// Several bindings can share a key. Command+Tab and Shift+Command+Tab
  /// both use Tab. The binding whose modifiers are all down, and that
  /// requires the most of them, is the one the hold is. A tie between
  /// two directions stops rather than guessing.
  static func directionWhileHeld(
    bindings: [Binding],
    keyCode: UInt16,
    held: HeldModifiers
  ) -> Direction? {
    let matches = bindings.filter { $0.keyCode == keyCode && held.contains($0.modifiers) }
    guard let narrowest = matches.map(\.modifiers.count).max() else { return nil }
    let closest = matches.filter { $0.modifiers.count == narrowest }
    guard let direction = closest.first?.direction else { return nil }
    guard closest.allSatisfy({ $0.direction == direction }) else { return nil }
    return direction
  }

  /// Whether this look moves, and which way.
  ///
  /// The key has to still be down, the panel has to still be walking
  /// presses, and the held modifiers have to name a direction. Any one
  /// failing ends the hold.
  static func tick(
    keyIsDown: Bool,
    panelStillWalking: Bool,
    direction: Direction?
  ) -> Step {
    guard keyIsDown, panelStillWalking, let direction else { return .stop }
    return .move(direction)
  }

  /// Clamps a delay and an interval into a timing a clock can wait on.
  ///
  /// A negative delay is the same as none. A zero interval would spin
  /// the run loop for as long as the key stayed down, so it is lifted
  /// to one millisecond. That floor is below any repeat rate macOS
  /// offers in Keyboard settings.
  static func timing(initialDelay: Duration, interval: Duration) -> Timing {
    Timing(
      initialDelay: max(.zero, initialDelay),
      interval: max(.milliseconds(1), interval)
    )
  }

}
