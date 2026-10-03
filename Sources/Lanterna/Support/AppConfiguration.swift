import Foundation

// MARK: - AppConfiguration

// Mirrors ConfigSchema.pkl in Swift. Change the schema first, then mirror
// it here, and keep the three (schema, types, scaffold) as one. CI checks
// the schema's rendering against config/schema-snapshot.json, which is the
// mechanical part of the sync; the mirroring itself is by hand.
//
// The runtime never evaluates Pkl. This file carries the schema's shape,
// defaults and validation into Swift, where the strictness lives.

/// The known keys of the config file, and nothing else.
///
/// A file holding any other key is invalid as a whole (FR-005). The check is
/// written out rather than derived from a `Decodable` struct because decoding
/// ignores unknown keys, which would silently accept them.
enum AppConfiguration {
  /// The schema generation this build understands.
  static let currentVersion = 1

  /// Every key there is. Anything else in the file is an unknown key.
  static let knownKeys: Set = [
    "version",
    "sampleCount",
    "stopMonitorEvery",
    "otherSpaceMode",
    "hiddenAppMode",
    "minimizedMode",
    "fullscreenMode",
    "windowlessAppMode",
    "appearanceMode",
    "romajiScope",
    "launchAtLogin",
    "logLevel",
    "saveLogsToDisk",
    "updateCheckEnabled",
    "updateChannel",
    "exclusions",
    "shortcutMemoryLength",
    "fuzzyMatchEnabled",
    "resultOrder",
    "keybindings",
    "textScale",
    "displayTarget",
    "panelWidth",
    "windowScope",
    "grouping",
    "otherSpacePlacement",
    "hiddenAppPlacement",
    "minimizedPlacement",
    "fullscreenPlacement",
    "windowlessAppPlacement",
    "groupCount",
    "groupHeadingStyle",
    "groupNames",
    "groupAssignments",
  ]

  /// The scaffold written when no file exists (FR-012).
  ///
  /// Absent keys mean their defaults, so the scaffold holds the version
  /// alone. Generated from the schema's defaults.
  static let scaffoldJSON = "{\n  \"version\": 1\n}\n"
}

// MARK: - ValidConfiguration

/// The validated contents of the config file.
///
/// `nil` fields mean absent, which means the long-standing behaviour:
/// live windows for `sampleCount`, an ordinary run for `stopMonitorEvery`.
struct ValidConfiguration: Equatable, Sendable {

  // MARK: Lifecycle

  init(
    version: Int,
    sampleCount: Int?,
    stopMonitorEverySeconds: Int?,
    otherSpaceMode: DisplayMode? = nil,
    hiddenAppMode: DisplayMode? = nil,
    minimizedMode: DisplayMode? = nil,
    fullscreenMode: DisplayMode? = nil,
    windowlessAppMode: DisplayMode? = nil,
    appearanceMode: AppearanceMode? = nil,
    romajiScope: RomajiScope? = nil,
    launchAtLogin: Bool? = nil,
    saveLogsToDisk: Bool? = nil,
    updateCheckEnabled: Bool? = nil,
    updateChannel: String? = nil,
    exclusions: [ExclusionEntry]? = nil,
    shortcutMemoryLength: Int? = nil,
    fuzzyMatchEnabled: Bool? = nil,
    resultOrder: String? = nil,
    textScale: Double? = nil,
    displayTarget: DisplayTarget? = nil,
    panelWidth: Double? = nil,
    windowScope: WindowScope? = nil,
    grouping: GroupingMode? = nil,
    subgroupPlacements: [DisplaySubgroup: SubgroupPlacement] = [:],
    groupCount: Int? = nil,
    groupHeadingStyle: GroupHeadingStyle? = nil,
    groupNames: [Int: String] = [:],
    groupAssignments: [GroupAssignment] = [],
    keyBindings: KeyBindingTable = .defaults,
    keyBindingSection: [KeyBindingAction: [RawKeyBinding]]? = nil
  ) {
    self.version = version
    self.sampleCount = sampleCount
    self.stopMonitorEverySeconds = stopMonitorEverySeconds
    self.otherSpaceMode = otherSpaceMode
    self.hiddenAppMode = hiddenAppMode
    self.minimizedMode = minimizedMode
    self.fullscreenMode = fullscreenMode
    self.windowlessAppMode = windowlessAppMode
    self.appearanceMode = appearanceMode
    self.romajiScope = romajiScope
    self.launchAtLogin = launchAtLogin
    self.saveLogsToDisk = saveLogsToDisk
    self.updateCheckEnabled = updateCheckEnabled
    self.updateChannel = updateChannel
    self.exclusions = exclusions
    self.shortcutMemoryLength = shortcutMemoryLength
    self.fuzzyMatchEnabled = fuzzyMatchEnabled
    self.resultOrder = resultOrder
    self.textScale = textScale
    self.displayTarget = displayTarget
    self.panelWidth = panelWidth
    self.windowScope = windowScope
    self.grouping = grouping
    self.subgroupPlacements = subgroupPlacements
    self.groupCount = groupCount
    self.groupHeadingStyle = groupHeadingStyle
    self.groupNames = groupNames
    self.groupAssignments = groupAssignments
    self.keyBindings = keyBindings
    self.keyBindingSection = keyBindingSection
  }

  // MARK: Internal

  var version: Int
  var sampleCount: Int?
  var stopMonitorEverySeconds: Int?
  var otherSpaceMode: DisplayMode?
  var hiddenAppMode: DisplayMode?
  var minimizedMode: DisplayMode?
  var fullscreenMode: DisplayMode?
  var windowlessAppMode: DisplayMode?
  var appearanceMode: AppearanceMode?
  var romajiScope: RomajiScope?
  var launchAtLogin: Bool?
  /// Whether each launch's log lines are kept on disk. Nil means absent,
  /// which means on.
  var saveLogsToDisk: Bool?
  var updateCheckEnabled: Bool?
  var updateChannel: String?
  /// The raw exclusion entries. Nil means absent, which means no exclusions.
  var exclusions: [ExclusionEntry]?
  /// How many characters of a query the shortcut memory covers. Nil means
  /// absent, which means 5. 0 means off.
  var shortcutMemoryLength: Int?
  /// Whether subsequence queries match as well as substrings. Nil means
  /// absent, which means on.
  var fuzzyMatchEnabled: Bool?
  /// The raw ordering word. Nil means absent, which means "mru".
  /// Kept as a string like `updateChannel`; the enum lives with T018.
  var resultOrder: String?
  /// The panel text and icon scale multiplier. Nil means absent, which
  /// means 1.0 (the current size). Only the five steps count; anything
  /// else falls back with a note instead of invalidating the file.
  var textScale: Double?
  /// Which display the panel opens on. Nil means absent, which means
  /// the menu-bar display.
  var displayTarget: DisplayTarget?
  /// The panel width multiplier. Nil means absent, which means 1.0
  /// (the current width). Only the five steps count; anything else
  /// falls back with a note instead of invalidating the file.
  var panelWidth: Double?
  /// Which applications' rows each appearance starts on. Nil means
  /// absent, which means every application.
  var windowScope: WindowScope?
  /// How the list groups its rows. Nil means absent, which means one list.
  var grouping: GroupingMode?
  /// Where each kind's parked section goes once grouped, for the kinds
  /// the file names. A kind left out goes to the end of the list.
  var subgroupPlacements: [DisplaySubgroup: SubgroupPlacement]
  /// How many manual groups there are. Nil means absent, which means 1.
  var groupCount: Int?
  /// What manual group headings say. Nil means absent, which means the number.
  var groupHeadingStyle: GroupHeadingStyle?
  /// The names given to manual groups. Empty means absent.
  var groupNames: [Int: String]
  /// The applications assigned to manual groups, in file order with the
  /// unreadable and repeated entries left out. Empty means absent.
  var groupAssignments: [GroupAssignment]
  /// The resolved key bindings. Never nil: absent means all defaults.
  var keyBindings: KeyBindingTable
  /// The customized section as spelled, kept so saving writes back what
  /// lost rather than what won. Nil means absent, meaning all defaults.
  var keyBindingSection: [KeyBindingAction: [RawKeyBinding]]?

}

// MARK: - ConfigDecodeError

/// Why a file could not be used. The text after each case is the reason
/// alone, for the `config invalid (<reason>)` diagnostics line.
enum ConfigDecodeError: Error, Equatable, Sendable {
  case notJSONObject
  case emptyFile
  case invalidVersion(String)
  case newerVersion(Int)
  case unknownKey(String)
  case invalidValue(key: String)

  // MARK: Internal

  var reason: String {
    switch self {
    case .notJSONObject:
      "not a JSON object"
    case .emptyFile:
      "file is empty"
    case .invalidVersion(let raw):
      "invalid version \(raw)"
    case .newerVersion(let found):
      "version \(found) is newer than \(AppConfiguration.currentVersion)"
    case .unknownKey(let key):
      "unknown key \"\(key)\""
    case .invalidValue(let key):
      "\(key) is not a valid value"
    }
  }
}

// MARK: - DecodedConfiguration

/// What decoding found, including whether the version was assumed.
struct DecodedConfiguration: Equatable, Sendable {
  var config: ValidConfiguration
  /// True when the file held no version and 1 was assumed (R4).
  var assumedVersion: Bool
  /// One entry per keybinding fallback, for the diagnostics lines.
  var keyBindingIssues = [KeyBindingIssue]()
  /// The fallback note when the text scale was present but invalid.
  /// Nil means absent or valid, which means nothing to report.
  var textScaleIssue: String?
  /// The fallback note when the panel width was present but invalid.
  /// Nil means absent or valid, which means nothing to report.
  var panelWidthIssue: String?
  /// Retired keys the file still held, read past without a look at their
  /// values, for one diagnostics line each.
  var deprecatedKeys = [String]()
  /// One entry per group assignment left out, for the diagnostics lines.
  var groupAssignmentIssues = [GroupAssignmentIssue]()
}

// MARK: - ConfigLoadOutcome

// What the launch-time load found.

enum ConfigLoadOutcome: Equatable, Sendable {
  case loaded(DecodedConfiguration)
  case created
  case failed(reason: String)
}

extension AppConfiguration {

  // MARK: Internal

  /// Loads the file or scaffolds it when missing.
  ///
  /// The only place that touches the file besides the scaffold write:
  /// existing files are read and never written (FR-013). Returns the
  /// outcome with the file URL so callers can say where in diagnostics.
  static func loadOrScaffold(applicationSupport: URL) -> (ConfigLoadOutcome, URL) {
    let url = configFileURL(applicationSupport: applicationSupport)
    guard FileManager.default.fileExists(atPath: url.path) else {
      do {
        try writeScaffold(to: url)
        return (.created, url)
      } catch {
        return (.failed(reason: "cannot create file"), url)
      }
    }
    guard let data = try? Data(contentsOf: url) else {
      return (.failed(reason: "cannot read file"), url)
    }
    switch decode(data) {
    case .success(let decoded):
      return (.loaded(decoded), url)
    case .failure(let error):
      return (.failed(reason: error.reason), url)
    }
  }

  /// Reads the file's bytes into validated settings.
  ///
  /// A pure function over bytes so every accepted and rejected shape is
  /// unit-testable, the way `LaunchArguments.parse` is over arguments.
  /// Anything outside the schema invalidates the whole file, except the
  /// lenient keybindings entries and text scale, which fall back with
  /// diagnostics instead of failing the file.
  static func decode(_ data: Data) -> Result<DecodedConfiguration, ConfigDecodeError> {
    let dict: [String: Any]
    switch parseObject(data) {
    case .success(let parsed):
      dict = parsed
    case .failure(let error):
      return .failure(error)
    }
    let version: Int
    let assumed: Bool
    switch checkedVersion(dict) {
    case .success(let found):
      (version, assumed) = found
    case .failure(let error):
      return .failure(error)
    }
    let sampleCount: Int?
    let stopMonitorEvery: Int?
    switch checkedCountOptions(dict) {
    case .success(let found):
      (sampleCount, stopMonitorEvery) = found
    case .failure(let error):
      return .failure(error)
    }
    switch checkedConfiguration(
      dict,
      version: version,
      sampleCount: sampleCount,
      stopMonitorEverySeconds: stopMonitorEvery
    ) {
    case .success(let config):
      return resolvedKeyBindings(dict, data: data, config: config, assumed: assumed)
        .flatMap { withGroupAssignments(dict, decoded: $0) }

    case .failure(let error):
      return .failure(error)
    }
  }

  /// The values this run uses. The command line wins where it says
  /// anything; the file covers the rest. The command line never reaches
  /// the file. Display modes and the appearance mode have no flag, so
  /// the file always covers them.
  static func effectiveOptions(
    file: ValidConfiguration,
    cli: LaunchArguments.Options
  ) -> LaunchArguments.Options {
    LaunchArguments.Options(
      sampleCount: cli.sampleCount ?? file.sampleCount,
      stopMonitorEvery: cli.stopMonitorEvery
        ?? file.stopMonitorEverySeconds.map { .seconds($0) },
      displayModes: DisplayModes.effective(from: file),
      exclusionEntries: file.exclusions ?? [],
      appearanceMode: AppearanceMode.effective(from: file),
      searchSettings: SearchSettings.effective(from: file),
      keyBindings: file.keyBindings,
      textScale: TextScaleLevel.effective(from: file),
      displayTarget: DisplayTarget.effective(from: file),
      panelWidth: PanelWidth.effective(from: file)
    )
  }

  /// Where the file lives under the given Application Support directory.
  ///
  /// The directory is a parameter rather than read here, so tests pass a
  /// temporary one and only `main.swift` resolves the real one (R8).
  static func configFileURL(applicationSupport: URL) -> URL {
    applicationSupport
      .appendingPathComponent("Lanterna", isDirectory: true)
      .appendingPathComponent("config.json")
  }

  /// Writes the scaffold. Only for files that do not exist (FR-012);
  /// callers check first, because existing files are never touched (FR-013).
  static func writeScaffold(to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(scaffoldJSON.utf8).write(to: url, options: .atomic)
  }

  // MARK: Private

  /// Parses bytes into a JSON object, refusing anything else.
  private static func parseObject(_ data: Data) -> Result<[String: Any], ConfigDecodeError> {
    guard !data.isEmpty else { return .failure(.emptyFile) }
    let raw: Any
    do {
      raw = try JSONSerialization.jsonObject(with: data)
    } catch {
      return .failure(.notJSONObject)
    }
    guard let dict = raw as? [String: Any] else { return .failure(.notJSONObject) }
    // Sorted so the reported key is stable across runs.
    for key in dict.keys.sorted() where !knownKeys.contains(key) {
      return .failure(.unknownKey(key))
    }
    return .success(dict)
  }

  /// Reads the version, assuming 1 when absent (R4).
  private static func checkedVersion(_ dict: [String: Any]) -> Result<(Int, Bool), ConfigDecodeError> {
    guard let rawVersion = dict["version"] else { return .success((currentVersion, true)) }
    guard let version = jsonInt(rawVersion) else {
      return .failure(.invalidVersion("\(rawVersion)"))
    }
    guard version <= currentVersion else { return .failure(.newerVersion(version)) }
    return .success((version, false))
  }

  /// Reads the display-mode keys into the configuration.
  private static func checkedDisplayModes(
    _ dict: [String: Any],
    into config: inout ValidConfiguration
  ) -> Result<Void, ConfigDecodeError> {
    let keys: [(String, WritableKeyPath<ValidConfiguration, DisplayMode?>)] = [
      ("otherSpaceMode", \.otherSpaceMode),
      ("hiddenAppMode", \.hiddenAppMode),
      ("minimizedMode", \.minimizedMode),
      ("fullscreenMode", \.fullscreenMode),
      ("windowlessAppMode", \.windowlessAppMode),
    ]
    for (key, path) in keys {
      switch checkedOptionalMode(dict, key: key) {
      case .success(let found):
        config[keyPath: path] = found
      case .failure(let error):
        return .failure(error)
      }
    }
    return .success(())
  }

  /// Assembles the validated configuration, reading the display modes,
  /// then the appearance mode, and then, last, the romaji scope.
  private static func checkedConfiguration(
    _ dict: [String: Any],
    version: Int,
    sampleCount: Int?,
    stopMonitorEverySeconds: Int?
  ) -> Result<ValidConfiguration, ConfigDecodeError> {
    var config = ValidConfiguration(
      version: version,
      sampleCount: sampleCount,
      stopMonitorEverySeconds: stopMonitorEverySeconds
    )
    switch checkedDisplayModes(dict, into: &config) {
    case .success:
      break
    case .failure(let error):
      return .failure(error)
    }
    switch checkedOptionalAppearance(dict, key: "appearanceMode") {
    case .success(let found):
      config.appearanceMode = found
    case .failure(let error):
      return .failure(error)
    }
    switch checkedOptionalRomajiScope(dict, key: "romajiScope") {
    case .success(let found):
      config.romajiScope = found
    case .failure(let error):
      return .failure(error)
    }
    switch checkedSwitches(dict, into: &config) {
    case .success:
      break
    case .failure(let error):
      return .failure(error)
    }
    switch checkedOptionalExclusions(dict, key: "exclusions") {
    case .success(let found):
      config.exclusions = found
    case .failure(let error):
      return .failure(error)
    }
    // Chained without another switch: this function already stands at
    // the complexity limit, and the helpers report their own failures.
    return checkedSearchSettings(dict, into: &config)
      .flatMap { checkedListing(dict, into: &config) }
      .flatMap { checkedDisplayTarget(dict, into: &config) }
      .map { _ in config }
  }

}
