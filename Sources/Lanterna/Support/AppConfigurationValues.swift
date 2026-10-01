import Foundation
import Logging

/// One optional key at a time, split out when the decoding file reached
/// the file-length limit. The shape of the file stays in `AppConfiguration`;
/// everything that reads a single key lives here.
extension AppConfiguration {
  /// Keys the file may still hold from earlier builds. Their values are
  /// never looked at, so whatever they hold keeps the rest of the file in
  /// force.
  static let deprecatedKeys = ["logLevel"]

  /// Reads the on-off and channel keys together, so the assembly stays small.
  static func checkedSwitches(
    _ dict: [String: Any],
    into config: inout ValidConfiguration
  ) -> Result<Void, ConfigDecodeError> {
    switch checkedOptionalBool(dict, key: "saveLogsToDisk") {
    case .success(let found):
      config.saveLogsToDisk = found
    case .failure(let error):
      return .failure(error)
    }
    switch checkedOptionalBool(dict, key: "launchAtLogin") {
    case .success(let found):
      config.launchAtLogin = found
    case .failure(let error):
      return .failure(error)
    }
    switch checkedOptionalBool(dict, key: "updateCheckEnabled") {
    case .success(let found):
      config.updateCheckEnabled = found
    case .failure(let error):
      return .failure(error)
    }
    switch checkedOptionalChannel(dict, key: "updateChannel") {
    case .success(let found):
      config.updateChannel = found
    case .failure(let error):
      return .failure(error)
    }
    return .success(())
  }

  /// Reads one optional integer key with its lower bound.
  static func checkedOptionalInt(
    _ dict: [String: Any],
    key: String,
    minimum: Int
  ) -> Result<Int?, ConfigDecodeError> {
    guard let rawValue = dict[key] else { return .success(nil) }
    guard let value = jsonInt(rawValue), value >= minimum else {
      return .failure(.invalidValue(key: key))
    }
    return .success(value)
  }

  /// Reads the count keys together, so `decode` stays small.
  static func checkedCountOptions(_ dict: [String: Any]) -> Result<
    (Int?, Int?),
    ConfigDecodeError
  > {
    let sampleCount: Int?
    switch checkedOptionalInt(dict, key: "sampleCount", minimum: 0) {
    case .success(let found):
      sampleCount = found
    case .failure(let error):
      return .failure(error)
    }
    let stopMonitorEvery: Int?
    switch checkedOptionalInt(dict, key: "stopMonitorEvery", minimum: 1) {
    case .success(let found):
      stopMonitorEvery = found
    case .failure(let error):
      return .failure(error)
    }
    return .success((sampleCount, stopMonitorEvery))
  }

  /// Reads one optional boolean key. Only a real boolean counts:
  /// integers are refused the way booleans are refused for integers.
  static func checkedOptionalBool(
    _ dict: [String: Any],
    key: String
  ) -> Result<Bool?, ConfigDecodeError> {
    guard let rawValue = dict[key] else { return .success(nil) }
    guard
      let number = rawValue as? NSNumber,
      String(cString: number.objCType) == "c"
    else {
      return .failure(.invalidValue(key: key))
    }
    return .success(number.boolValue)
  }

  /// Reads one optional display-mode key. Anything but a `DisplayMode`
  /// word invalidates the whole file, like any other bad value.
  static func checkedOptionalMode(
    _ dict: [String: Any],
    key: String
  ) -> Result<DisplayMode?, ConfigDecodeError> {
    guard let rawValue = dict[key] else { return .success(nil) }
    guard let text = rawValue as? String, let mode = DisplayMode(rawValue: text) else {
      return .failure(.invalidValue(key: key))
    }
    return .success(mode)
  }

  /// Reads the optional appearance-mode key. Anything but an
  /// `AppearanceMode` word invalidates the whole file, like any other
  /// bad value.
  static func checkedOptionalAppearance(
    _ dict: [String: Any],
    key: String
  ) -> Result<AppearanceMode?, ConfigDecodeError> {
    guard let rawValue = dict[key] else { return .success(nil) }
    guard let text = rawValue as? String, let mode = AppearanceMode(rawValue: text) else {
      return .failure(.invalidValue(key: key))
    }
    return .success(mode)
  }

  /// Reads the optional romaji-scope key. Anything but a
  /// `RomajiScope` word invalidates the whole file, like any other
  /// bad value.
  static func checkedOptionalRomajiScope(
    _ dict: [String: Any],
    key: String
  ) -> Result<RomajiScope?, ConfigDecodeError> {
    guard let rawValue = dict[key] else { return .success(nil) }
    guard let text = rawValue as? String, let scope = RomajiScope(rawValue: text) else {
      return .failure(.invalidValue(key: key))
    }
    return .success(scope)
  }

  /// Reads the three search-quality keys together, so the assembly stays
  /// small. The length bound is 0 to 5: the lower bound rides on the
  /// shared reader, the upper bound refuses the whole file, like any
  /// other bad value.
  static func checkedSearchSettings(
    _ dict: [String: Any],
    into config: inout ValidConfiguration
  ) -> Result<Void, ConfigDecodeError> {
    switch checkedOptionalInt(dict, key: "shortcutMemoryLength", minimum: 0) {
    case .success(let found):
      guard found.map({ $0 <= 5 }) ?? true else {
        return .failure(.invalidValue(key: "shortcutMemoryLength"))
      }
      config.shortcutMemoryLength = found

    case .failure(let error):
      return .failure(error)
    }
    switch checkedOptionalBool(dict, key: "fuzzyMatchEnabled") {
    case .success(let found):
      config.fuzzyMatchEnabled = found
    case .failure(let error):
      return .failure(error)
    }
    switch checkedOptionalResultOrder(dict, key: "resultOrder") {
    case .success(let found):
      config.resultOrder = found
    case .failure(let error):
      return .failure(error)
    }
    return .success(())
  }

  /// Reads the optional ordering word. Only the two known words count:
  /// anything else invalidates the whole file, like any other bad value.
  static func checkedOptionalResultOrder(
    _ dict: [String: Any],
    key: String
  ) -> Result<String?, ConfigDecodeError> {
    guard let rawValue = dict[key] else { return .success(nil) }
    guard
      let text = rawValue as? String,
      text == "mru" || text == "score"
    else {
      return .failure(.invalidValue(key: key))
    }
    return .success(text)
  }

  /// Reads one optional channel key. Only the two known words count:
  /// anything else invalidates the whole file, like any other bad value.
  static func checkedOptionalChannel(
    _ dict: [String: Any],
    key: String
  ) -> Result<String?, ConfigDecodeError> {
    guard let rawValue = dict[key] else { return .success(nil) }
    guard
      let text = rawValue as? String,
      text == "stable" || text == "beta"
    else {
      return .failure(.invalidValue(key: key))
    }
    return .success(text)
  }

  /// Reads the optional exclusion list. The value must be an array;
  /// anything else invalidates the whole file. Elements that are not
  /// objects, or lack string app and titlePattern pairs, or carry
  /// extra keys, are skipped one by one while valid elements are kept.
  /// Value problems stay raw here: compiling reports what it skips, so
  /// decoding never decides what counts as unreadable.
  static func checkedOptionalExclusions(
    _ dict: [String: Any],
    key: String
  ) -> Result<[ExclusionEntry]?, ConfigDecodeError> {
    guard let rawValue = dict[key] else { return .success(nil) }
    guard let items = rawValue as? [Any] else {
      return .failure(.invalidValue(key: key))
    }
    var entries = [ExclusionEntry]()
    for item in items {
      guard
        let element = item as? [String: Any],
        Set(element.keys) == Set(["app", "titlePattern"]),
        let app = element["app"] as? String,
        let titlePattern = element["titlePattern"] as? String
      else {
        continue
      }
      entries.append(ExclusionEntry(app: app, titlePattern: titlePattern))
    }
    return .success(entries)
  }

  /// A JSON integer and nothing else.
  ///
  /// Booleans are refused by their Objective-C type: an `is Bool` check
  /// wrongly matches integer 1, so only the `c` type is turned away.
  static func jsonInt(_ value: Any) -> Int? {
    if let number = value as? NSNumber, String(cString: number.objCType) == "c" {
      return nil
    }
    return value as? Int
  }

  /// A JSON number and nothing else.
  ///
  /// Booleans are refused the way `jsonInt` refuses them. Integers
  /// count as their double value, so a spelled `1` reads as `1.0`.
  static func jsonDouble(_ value: Any) -> Double? {
    if let number = value as? NSNumber, String(cString: number.objCType) == "c" {
      return nil
    }
    return (value as? NSNumber)?.doubleValue
  }

  /// Reads the optional text-scale key leniently: absent means the
  /// standard size, a non-standard step wins, the standard step reads
  /// as absent so an explicit 1.0 stays omitted on save, and anything
  /// else falls back to standard with a note instead of failing the file.
  static func checkedOptionalTextScale(
    _ dict: [String: Any]
  ) -> (value: Double?, issue: String?) {
    guard let rawValue = dict["textScale"] else { return (nil, nil) }
    guard let factor = jsonDouble(rawValue), let level = TextScaleLevel(factor: factor) else {
      return (nil, "textScale is not a valid value; using 1.0")
    }
    if level == .standard {
      return (nil, nil)
    }
    return (factor, nil)
  }

  /// Reads the keybindings section leniently: malformed entries and
  /// unknown actions are dropped one by one with issues, never failing
  /// the file. Only a section that is not an object at all is a bad
  /// value, like any other misshapen key.
  static func checkedOptionalKeyBindings(
    _ dict: [String: Any]
  ) -> Result<([KeyBindingAction: [RawKeyBinding]], [KeyBindingIssue]), ConfigDecodeError> {
    guard let rawValue = dict["keybindings"] else { return .success(([:], [])) }
    guard let section = rawValue as? [String: Any] else {
      return .failure(.invalidValue(key: "keybindings"))
    }
    var out = [KeyBindingAction: [RawKeyBinding]]()
    var issues = [KeyBindingIssue]()
    for name in section.keys.sorted() {
      guard let action = KeyBindingAction(rawValue: name) else {
        issues.append(KeyBindingIssue(
          action: nil,
          reason: .invalid,
          detail: "unknown action \(name)"
        ))
        continue
      }
      guard let raws = section[name] as? [Any] else {
        issues.append(KeyBindingIssue(
          action: action,
          reason: .invalid,
          detail: "\(name) is not a list"
        ))
        continue
      }
      var entries = [RawKeyBinding]()
      for raw in raws {
        guard
          let entry = raw as? [String: Any],
          Set(entry.keys) == Set(["keyCode", "modifiers"]),
          let keyCode = jsonInt(entry["keyCode"] as Any),
          let modifiers = entry["modifiers"] as? [String]
        else {
          issues.append(KeyBindingIssue(
            action: action,
            reason: .invalid,
            detail: "\(name) holds a malformed entry"
          ))
          continue
        }
        entries.append(RawKeyBinding(keyCode: keyCode, modifiers: modifiers))
      }
      out[action] = entries
    }
    return .success((out, issues))
  }

  /// Resolves the lenient sections over an otherwise valid file.
  ///
  /// The keybindings section is lenient where the rest of the file is
  /// strict: bad entries fall back per item with diagnostics, while a
  /// section that is not an object at all invalidates the whole file
  /// like any other bad value. Declaration order comes from the file
  /// text, because JSON objects carry no order of their own. The text
  /// scale is lenient the same way on its own: a present but invalid
  /// value falls back to standard with a note.
  static func resolvedKeyBindings(
    _ dict: [String: Any],
    data: Data,
    config: ValidConfiguration,
    assumed: Bool
  ) -> Result<DecodedConfiguration, ConfigDecodeError> {
    switch checkedOptionalKeyBindings(dict) {
    case .success((let section, let decodeIssues)):
      var config = config
      let text = String(data: data, encoding: .utf8) ?? ""
      let order = KeyBindingResolver.declarationOrder(in: text)
      let (table, resolveIssues) = KeyBindingResolver.resolve(section, order: order)
      config.keyBindings = table
      config.keyBindingSection = section.isEmpty ? nil : section
      let (textScale, textScaleIssue) = checkedOptionalTextScale(dict)
      config.textScale = textScale
      return .success(DecodedConfiguration(
        config: config,
        assumedVersion: assumed,
        keyBindingIssues: decodeIssues + resolveIssues,
        textScaleIssue: textScaleIssue,
        deprecatedKeys: deprecatedKeys.filter { dict[$0] != nil }
      ))

    case .failure(let error):
      return .failure(error)
    }
  }
}
