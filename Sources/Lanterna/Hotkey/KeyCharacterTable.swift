import Carbon.HIToolbox
import Foundation

// MARK: - KeyCharacterTable

/// The letter or digit each key types, with and without Shift.
///
/// Fast Search reads its characters from key codes on the tap's own
/// thread, where there is no `NSEvent` to ask, and the string an event
/// carries is the one with every modifier applied (Option-S gives `ß`).
/// This table is what the current keyboard layout types for each key with
/// no modifier but Shift, so the first letter and the ones after it read
/// the same way the panel's own typing does.
///
/// Only a single ASCII letter or digit is kept. A key that types a symbol,
/// such as Shift-3 on a US layout, has no entry, and that absence is what
/// stops such a press from starting a search.
struct KeyCharacterTable: Equatable, Sendable {

  // MARK: Lifecycle

  /// Builds the table by asking `translate` for every key code, plain and
  /// shifted. The layout lookup sits behind the closure so the table can
  /// be built from a fixed layout.
  init(translating translate: (_ keyCode: UInt16, _ shift: Bool) -> String?) {
    var plain = [UInt16: Character]()
    var shifted = [UInt16: Character]()
    for keyCode in UInt16(0) ..< 128 {
      plain[keyCode] = Self.letterOrDigit(translate(keyCode, false))
      shifted[keyCode] = Self.letterOrDigit(translate(keyCode, true))
    }
    self.plain = plain
    self.shifted = shifted
  }

  // MARK: Internal

  /// A table with no entries, for when no layout could be read.
  static let empty = KeyCharacterTable(translating: { _, _ in nil })

  /// The table for the current ASCII-capable layout.
  ///
  /// The ASCII-capable layout rather than the selected source: with an
  /// input method selected, the keys still type through the layout under
  /// it. Main actor because the input source calls are only safe there.
  @MainActor
  static func current() -> KeyCharacterTable {
    guard
      let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
      let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else {
      return .empty
    }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    let keyboardType = UInt32(LMGetKbdType())
    return data.withUnsafeBytes { buffer in
      guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
        return .empty
      }
      return KeyCharacterTable { keyCode, shift in
        translate(layout, keyCode: keyCode, shift: shift, keyboardType: keyboardType)
      }
    }
  }

  /// The letter or digit this key types, or nil.
  func character(keyCode: UInt16, shift: Bool) -> Character? {
    shift ? shifted[keyCode] : plain[keyCode]
  }

  // MARK: Private

  private let plain: [UInt16: Character]
  private let shifted: [UInt16: Character]

  private static func letterOrDigit(_ text: String?) -> Character? {
    guard let text, text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else {
      return nil
    }
    guard scalar.isASCII, scalar.properties.isAlphabetic || ("0" ... "9").contains(scalar) else {
      return nil
    }
    return Character(scalar)
  }

  private static func translate(
    _ layout: UnsafePointer<UCKeyboardLayout>,
    keyCode: UInt16,
    shift: Bool,
    keyboardType: UInt32
  ) -> String? {
    var deadKeys: UInt32 = 0
    var length = 0
    var buffer = [UniChar](repeating: 0, count: 4)
    let modifierState: UInt32 = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
    let status = UCKeyTranslate(
      layout,
      keyCode,
      UInt16(kUCKeyActionDown),
      modifierState,
      keyboardType,
      OptionBits(kUCKeyTranslateNoDeadKeysMask),
      &deadKeys,
      buffer.count,
      &length,
      &buffer
    )
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: buffer, count: length)
  }

}

// MARK: - KeyCharacterTableWatch

/// Keeps the table current as the user switches input sources.
///
/// The table is rebuilt on the main actor and handed on whole; whoever
/// reads it off the main thread holds the value it was given.
@MainActor
final class KeyCharacterTableWatch {

  // MARK: Lifecycle

  init(
    read: @escaping @MainActor () -> KeyCharacterTable = KeyCharacterTable.current,
    center: DistributedNotificationCenter = .default()
  ) {
    self.read = read
    self.center = center
  }

  // MARK: Internal

  /// Hands over the current table now and again after every switch.
  func start(onChange: @escaping @MainActor (KeyCharacterTable) -> Void) {
    stop()
    self.onChange = onChange
    observer = center.addObserver(
      forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    refresh()
  }

  func stop() {
    if let observer {
      center.removeObserver(observer)
    }
    observer = nil
    onChange = nil
  }

  /// Reads the table again and hands it over.
  func refresh() {
    onChange?(read())
  }

  // MARK: Private

  private let read: @MainActor () -> KeyCharacterTable
  private let center: DistributedNotificationCenter
  private var observer: (any NSObjectProtocol)?
  private var onChange: (@MainActor (KeyCharacterTable) -> Void)?

}
