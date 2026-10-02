import Foundation

/// The keys deciding which rows the switcher lists and how it groups them,
/// read together so the assembly in `AppConfiguration` gains one call.
extension AppConfiguration {
  /// Reads the scope key into the configuration.
  static func checkedListing(
    _ dict: [String: Any],
    into config: inout ValidConfiguration
  ) -> Result<Void, ConfigDecodeError> {
    switch checkedOptionalWord(dict, key: "windowScope", as: WindowScope.self) {
    case .success(let found):
      config.windowScope = found
    case .failure(let error):
      return .failure(error)
    }
    return .success(())
  }

  /// The lines for the keys read above, in any order: the encoder sorts
  /// every line by its key.
  static func listingEntries(_ config: ValidConfiguration) -> [String] {
    var entries = [String]()
    if let windowScope = config.windowScope {
      entries.append(encodedString(key: "windowScope", value: windowScope.rawValue))
    }
    if let windowlessAppMode = config.windowlessAppMode {
      entries.append(encodedString(key: "windowlessAppMode", value: windowlessAppMode.rawValue))
    }
    return entries
  }

  /// Reads one optional key holding one word of a fixed set. Anything
  /// else invalidates the whole file, like any other bad value.
  static func checkedOptionalWord<Word: RawRepresentable<String>>(
    _ dict: [String: Any],
    key: String,
    as _: Word.Type
  ) -> Result<Word?, ConfigDecodeError> {
    guard let rawValue = dict[key] else { return .success(nil) }
    guard let text = rawValue as? String, let word = Word(rawValue: text) else {
      return .failure(.invalidValue(key: key))
    }
    return .success(word)
  }
}
