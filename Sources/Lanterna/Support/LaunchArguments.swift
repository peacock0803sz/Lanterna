import Foundation

/// The command-line options the app understands.
///
/// Parsing is a pure function over an argument array rather than a read of
/// `ProcessInfo`, so every accepted and rejected form is unit-testable.
enum LaunchArguments {

  // MARK: Internal

  /// Everything the command line asked for, as one value.
  ///
  /// A struct rather than one answer per flag. A parser that returned a
  /// single number could describe only one flag, and every flag after it
  /// would be another parameter threaded through to whoever receives them.
  struct Options: Equatable, Sendable {
    /// Draw this many fixture entries instead of the windows that are
    /// really open. `nil` lists the live windows.
    var sampleCount: Int?
    /// Stop the modifier monitor this often, so that it can be watched
    /// putting itself back. Absent in an ordinary run.
    var stopMonitorEvery: Duration?
    /// How the special kinds show. No flag sets it; the file covers it.
    var displayModes = DisplayModes.defaults
    /// The raw exclusion entries. No flag sets them; the file covers them.
    var exclusionEntries = [ExclusionEntry]()
    /// Which appearance the windows use. No flag sets it; the file covers it.
    var appearanceMode = AppearanceMode.system
    /// The three search-quality settings as one value. No flag sets
    /// them; the file covers them.
    var searchSettings = SearchSettings()
    /// The resolved key bindings. No flag sets them; the file covers
    /// them.
    var keyBindings = KeyBindingTable.defaults
    /// The panel text and icon scale step. No flag sets it; the file
    /// covers it.
    var textScale = TextScaleLevel.standard
    /// Which display the panel opens on. No flag sets it; the file
    /// covers it.
    var displayTarget = DisplayTarget.primary
    /// The panel width step. No flag sets it; the file covers it.
    var panelWidth = PanelWidth.standard
    /// The panel show delay in milliseconds. Nil means off. No flag
    /// sets it; the file covers it.
    var showDelayMs: Double?
    /// Whether hovering a row moves the selection. No flag sets it;
    /// the file covers it.
    var hoverSelect = false
    /// Whether scrolling moves the selection. No flag sets it;
    /// the file covers it.
    var scrollSelect = false
    /// Retired flags the command line still gave, read past, for one
    /// diagnostics line each.
    var retiredFlags = [String]()
  }

  /// What a flag will take, as one closed choice.
  ///
  /// A case per range rather than a number and a phrase side by side. Two
  /// fields can disagree — a flag refusing zero while its refusal tells the
  /// reader zero was fine — and that disagreement would show up only in the
  /// text of a rejection, which is the one place nothing looks. Here the two
  /// halves are one thing: the bound and the words for it are read off the
  /// same case, so neither can drift from the other.
  ///
  /// Closed on purpose. A range added later leaves both switches below short
  /// of a case, and the flag wanting it cannot be written down until its
  /// bound and its wording have both been supplied.
  enum AcceptedValues: Equatable, Sendable {
    case zeroOrMore
    case oneOrMore

    // MARK: Internal

    /// The smallest value accepted.
    var minimum: Int {
      switch self {
      case .zeroOrMore: 0
      case .oneOrMore: 1
      }
    }

    /// That bound, in the words a refusal uses.
    var described: String {
      switch self {
      case .zeroOrMore: "zero or more"
      case .oneOrMore: "one or more"
      }
    }
  }

  /// One flag, and what it will take.
  ///
  /// The bound and the words for it travel together because a refusal has to
  /// say which range was missed. Naming the flag but not its range would
  /// leave a reader knowing which value was rejected and not what would have
  /// been accepted instead.
  struct Flag: Equatable, Sendable {
    let name: String
    let accepts: AcceptedValues

    /// What the `--flag=value` form starts with.
    var inlinePrefix: String {
      name + "="
    }
  }

  /// Why an argument could not be used. The text is the reason alone; the
  /// usage line is `LaunchArguments.usage`.
  ///
  /// Each case that concerns a flag carries the flag itself rather than its
  /// name. The name alone would say which flag was wrong, and the whole
  /// point of naming it is to say which of two different ranges was missed.
  enum ParseError: Error, Equatable, CustomStringConvertible {
    case missingValue(Flag)
    case invalidValue(flag: Flag, value: String)
    case unknownOption(String)
    case duplicateFlag(Flag)

    // MARK: Internal

    var description: String {
      switch self {
      case .missingValue(let flag):
        "\(flag.name) needs a value"

      case .invalidValue(let flag, let value):
        "\"\(value)\" is not a whole number of \(flag.accepts.described) (\(flag.name))"

      case .unknownOption(let option):
        "unknown option \"\(option)\""

      case .duplicateFlag(let flag):
        "\(flag.name) given more than once"
      }
    }
  }

  static let sampleCountFlag = Flag(
    name: "--sample-count",
    accepts: .zeroOrMore
  )

  /// Whole seconds, and at least one of them. A period of zero would be a
  /// request to stop the monitor as fast as the loop can be asked to, which
  /// is a way of turning it off rather than a way of watching it recover.
  static let stopMonitorEveryFlag = Flag(
    name: "--stop-monitor-every",
    accepts: .oneOrMore
  )

  /// Every flag there is. Anything beginning with two dashes and absent from
  /// here, or from the retired ones, is an unknown option.
  static let allFlags = [sampleCountFlag, stopMonitorEveryFlag]

  /// Flags earlier builds took. Each is read past with the one value it
  /// may carry, so an old launch command still starts; a missing value
  /// is no error either. Left out of the usage line.
  static let retiredFlags = ["--log-level"]

  /// One line describing correct usage, for stderr.
  static let usage = "usage: Lanterna [\(sampleCountFlag.name) N]"
    + " [\(stopMonitorEveryFlag.name) SECONDS]"

  /// What the command line asked for. Both `--flag value` and `--flag=value`
  /// are accepted, for either flag, in any position and in any order. An
  /// unknown `--` option, a repeated flag and a missing or malformed value
  /// are usage errors.
  ///
  /// Single-dash arguments and bare values are ignored, because macOS and
  /// Xcode inject `-Key Value` pairs such as
  /// `-NSDocumentRevisionsDebugMode YES`. A single-dash misspelling,
  /// `-sample-count 5`, is therefore not caught, and the same hole is open
  /// for every flag: closing it would mean inspecting single-dash arguments,
  /// which cannot be told from the pairs the system puts there.
  static func parse(_ arguments: [String]) throws(ParseError) -> Options {
    // Collected by name and turned into the typed fields at the end. The
    // seconds become a `Duration` at that one point, so nothing further on
    // is ever handed a bare number whose unit it could take for
    // milliseconds.
    var values = [String: Int]()
    var retired = [String]()
    var index = arguments.index(after: arguments.startIndex)

    while index < arguments.endIndex {
      let argument = arguments[index]
      if let flag = allFlags.first(where: { argument == $0.name }) {
        // Asked before the value is looked for, so a flag given twice
        // reads as a repeat whichever of the two is also malformed.
        guard values[flag.name] == nil else {
          throw .duplicateFlag(flag)
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { throw .missingValue(flag) }
        try store(arguments[valueIndex], of: flag, values: &values)
        index = arguments.index(after: valueIndex)
      } else if let flag = allFlags.first(where: { argument.hasPrefix($0.inlinePrefix) }) {
        let rawValue = String(argument.dropFirst(flag.inlinePrefix.count))
        try store(rawValue, of: flag, values: &values)
        index = arguments.index(after: index)
      } else if let name = retiredFlags.first(where: { argument == $0 || argument.hasPrefix($0 + "=") }) {
        if !retired.contains(name) {
          retired.append(name)
        }
        index = arguments.index(after: index)
        // The separate value goes with the flag, unless what follows is
        // another flag.
        if argument == name, index < arguments.endIndex, !arguments[index].hasPrefix("-") {
          index = arguments.index(after: index)
        }
      } else if argument.hasPrefix("--") {
        throw .unknownOption(argument)
      } else {
        index = arguments.index(after: index)
      }
    }

    return Options(
      sampleCount: values[sampleCountFlag.name],
      stopMonitorEvery: values[stopMonitorEveryFlag.name].map { .seconds($0) },
      retiredFlags: retired
    )
  }

  // MARK: Private

  /// Files one flag's raw value under its name. Both forms share the
  /// repeat rule, so the guard lives here rather than once per form.
  private static func store(
    _ rawValue: String,
    of flag: Flag,
    values: inout [String: Int]
  ) throws(ParseError) {
    guard values[flag.name] == nil else {
      throw .duplicateFlag(flag)
    }
    values[flag.name] = try parsedValue(rawValue, of: flag)
  }

  private static func parsedValue(
    _ rawValue: String,
    of flag: Flag
  ) throws(ParseError) -> Int {
    guard let value = Int(rawValue), value >= flag.accepts.minimum else {
      throw .invalidValue(flag: flag, value: rawValue)
    }
    return value
  }

}
