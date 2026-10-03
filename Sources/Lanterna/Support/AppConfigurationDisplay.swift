import Foundation

/// The keys deciding where the panel opens and how wide it is, read
/// together so the assembly in `AppConfiguration` gains one call.
extension AppConfiguration {

  /// Reads the display-target key into the configuration. The target word
  /// is strict like the other words: anything else invalidates the whole
  /// file.
  static func checkedDisplayTarget(
    _ dict: [String: Any],
    into config: inout ValidConfiguration
  ) -> Result<Void, ConfigDecodeError> {
    switch checkedOptionalWord(dict, key: "displayTarget", as: DisplayTarget.self) {
    case .success(let found):
      config.displayTarget = found
    case .failure(let error):
      return .failure(error)
    }
    return .success(())
  }

  /// Reads the optional panel-width key leniently: absent means the
  /// standard width, a non-standard step wins, the standard step reads
  /// as absent so an explicit 1.0 stays omitted on save, and anything
  /// else falls back to standard with a note instead of failing the file.
  static func checkedOptionalPanelWidth(
    _ dict: [String: Any]
  ) -> (value: Double?, issue: String?) {
    guard let rawValue = dict["panelWidth"] else { return (nil, nil) }
    guard let factor = jsonDouble(rawValue), let step = PanelWidth(factor: factor) else {
      return (nil, "panelWidth is not a valid value; using 1.0")
    }
    if step == .standard {
      return (nil, nil)
    }
    return (factor, nil)
  }

  /// The lines for the keys read above, in any order: the encoder sorts
  /// every line by its key.
  static func displayEntries(_ config: ValidConfiguration) -> [String] {
    var entries = [String]()
    if let displayTarget = config.displayTarget {
      entries.append(encodedString(key: "displayTarget", value: displayTarget.rawValue))
    }
    if let panelWidth = config.panelWidth {
      entries.append(encodedDouble(key: "panelWidth", value: panelWidth))
    }
    return entries
  }

}
