import Carbon.HIToolbox
import Logging

// MARK: - InputSourceLock

/// Holds one keyboard input source for as long as the panel is up, and gives
/// the user's own back when it goes.
///
/// The keys reach the panel already rewritten by whatever watches the input
/// source: a Karabiner-Elements rule gated on a Japanese source turns
/// physical `a b c` into `k i s a d o` before the local monitor sees it. The
/// IME itself never sees panel keys, so nothing short of selecting another
/// source stops the rewriting.
///
/// A state machine rather than a flag and a saved ID, because the saved ID
/// only means something while a force is in place: `.holding` is the one
/// state that has an original to give back. Both moves are idempotent, so
/// the many ways the panel goes up (each press of a held Command+Tab, the
/// key-status watch taking keys back) and the many ways it comes down
/// (every exit, then quit) converge without counting.
///
/// Lives beside the panel's key input rather than in Model: it makes Carbon
/// calls the way `PanelKeyInput.swift` does, and Model holds pure values.
@MainActor
final class InputSourceLock {

  // MARK: Lifecycle

  /// Closures rather than a protocol, for the reason `LocalKeyEventChannel`
  /// gives: these are two free functions, and the real calls are the
  /// defaults so nothing outside a test learns there is a seam.
  init(
    currentSourceID: @escaping @MainActor () -> String? = InputSourceLock.liveCurrentSourceID,
    selectSource: @escaping @MainActor (String) -> Bool = InputSourceLock.liveSelectSource,
    writeLine: @escaping @MainActor (LogLine) -> Void = { line in
      guard Diagnostics.logger != nil else { return }
      Diagnostics.writeLine(line)
    }
  ) {
    self.currentSourceID = currentSourceID
    self.selectSource = selectSource
    self.writeLine = writeLine
  }

  // MARK: Internal

  /// Whether a force is in place, and what it would give back.
  enum State: Equatable {
    case idle
    /// `original` is what was selected when the force began; `forced` is
    /// kept beside it because the target may change before the release.
    case holding(original: String, forced: String)
  }

  private(set) var state = State.idle

  /// The source ID to force, or nil for off. Turning it off while a force
  /// is in place gives the user's source back at once, rather than leaving
  /// it stranded until a release that would no longer know to come.
  var target: String? {
    didSet {
      if target == nil {
        release()
      }
    }
  }

  /// Selects the target if nothing is held yet. Calling again while holding
  /// does nothing, so the forced source can never be captured as the
  /// original.
  func engage() {
    guard case .idle = state, let target else { return }
    guard let original = currentSourceID() else {
      writeLine(LogLine(.info, .panel, "input source unreadable; not forcing \(target)"))
      return
    }
    // Already there: nothing to give back, so stay idle and skip the call.
    guard original != target else { return }
    guard selectSource(target) else {
      writeLine(LogLine(.info, .panel, "input source \(target) could not be selected; kept \(original)"))
      return
    }
    state = .holding(original: original, forced: target)
    writeLine(LogLine(.info, .panel, "input source forced \(original) -> \(target)"))
  }

  /// Gives the original back if the forced source is still the one in
  /// place. A source other than the forced one stays: it is a newer choice
  /// than the one this would restore. Only the source in place at release
  /// is compared, so a hand pick that ends back on the forced source is
  /// indistinguishable from no pick and is restored over.
  ///
  /// Stays holding when the restore cannot happen, so the next release (the
  /// next panel exit, or quit) tries again instead of losing the original.
  func release() {
    guard case .holding(let original, let forced) = state else { return }
    guard let current = currentSourceID() else {
      writeLine(LogLine(.info, .panel, "input source unreadable; \(original) restore deferred"))
      return
    }
    guard current == forced else {
      state = .idle
      writeLine(LogLine(.info, .panel, "input source left at \(current); not restoring \(original)"))
      return
    }
    guard selectSource(original) else {
      writeLine(LogLine(.info, .panel, "input source \(original) could not be restored; left \(forced)"))
      return
    }
    state = .idle
    writeLine(LogLine(.info, .panel, "input source restored \(forced) -> \(original)"))
  }

  // MARK: Private

  private let currentSourceID: @MainActor () -> String?
  private let selectSource: @MainActor (String) -> Bool
  private let writeLine: @MainActor (LogLine) -> Void

}

// MARK: - Live calls

extension InputSourceLock {

  // MARK: Internal

  /// The selected keyboard input source. Not the keyboard layout: with
  /// Hiragana selected the layout reads ABC, and restoring that would never
  /// bring the IME back.
  static func liveCurrentSourceID() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    return stringProperty(source, kTISPropertyInputSourceID)
  }

  /// Selects the enabled source with this ID. A source that is disabled or
  /// gone is not in the list, so it answers false like any other failure.
  static func liveSelectSource(_ id: String) -> Bool {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard
      let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
      let source = list.first
    else {
      return false
    }
    return TISSelectInputSource(source) == noErr
  }

  /// The sources the menu-bar input menu offers: enabled, select-capable
  /// keyboard sources and input modes. A parent IME such as ATOK is not
  /// select-capable; its modes are, which is why each mode is its own entry.
  static func selectableSources() -> [InputSourceChoice] {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
      return []
    }
    return list.compactMap { source in
      guard
        boolProperty(source, kTISPropertyInputSourceIsSelectCapable),
        stringProperty(source, kTISPropertyInputSourceCategory) == kTISCategoryKeyboardInputSource as String,
        let id = stringProperty(source, kTISPropertyInputSourceID)
      else {
        return nil
      }
      return InputSourceChoice(id: id, name: stringProperty(source, kTISPropertyLocalizedName) ?? id)
    }
  }

  // MARK: Private

  private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
  }

  private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
    guard let raw = TISGetInputSourceProperty(source, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
  }

}

// MARK: - InputSourceChoice

/// One entry of the settings picker: stored by ID, shown by name.
struct InputSourceChoice: Hashable, Identifiable {
  let id: String
  let name: String
}
