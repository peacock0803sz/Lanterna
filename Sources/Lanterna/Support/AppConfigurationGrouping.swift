import Foundation

/// The keys deciding which rows the switcher lists and how it groups them,
/// read together so the assembly in `AppConfiguration` gains one call.
extension AppConfiguration {

  /// The placement key for each kind of parked section, in drawing order.
  static let placementKeys: [(String, DisplaySubgroup)] = [
    ("otherSpacePlacement", .otherSpace),
    ("hiddenAppPlacement", .hiddenApp),
    ("minimizedPlacement", .minimized),
    ("fullscreenPlacement", .fullscreen),
    ("windowlessAppPlacement", .windowlessApp),
  ]

  /// Reads the scope, grouping and placement keys into the configuration.
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
    switch checkedOptionalWord(dict, key: "numberScope", as: NumberScope.self) {
    case .success(let found):
      config.numberScope = found
    case .failure(let error):
      return .failure(error)
    }
    switch checkedOptionalWord(dict, key: "grouping", as: GroupingMode.self) {
    case .success(let found):
      config.grouping = found
    case .failure(let error):
      return .failure(error)
    }
    for (key, subgroup) in placementKeys {
      switch checkedOptionalWord(dict, key: key, as: SubgroupPlacement.self) {
      case .success(let found):
        config.subgroupPlacements[subgroup] = found
      case .failure(let error):
        return .failure(error)
      }
    }
    return checkedManualGroups(dict, into: &config)
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
    if let grouping = config.grouping {
      entries.append(encodedString(key: "grouping", value: grouping.rawValue))
    }
    for (key, subgroup) in placementKeys {
      if let placement = config.subgroupPlacements[subgroup] {
        entries.append(encodedString(key: key, value: placement.rawValue))
      }
    }
    return entries + manualGroupEntries(config)
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
