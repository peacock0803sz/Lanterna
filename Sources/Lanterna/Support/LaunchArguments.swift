import Foundation
import Logging

/// The command-line options the app understands.
///
/// Parsing is a pure function over an argument array rather than a read of
/// `ProcessInfo`, so every accepted and rejected form is unit-testable.
enum LaunchArguments {
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
        var displayModes: DisplayModes = .defaults
        /// The raw exclusion entries. No flag sets them; the file covers them.
        var exclusionEntries: [ExclusionEntry] = []
        /// Which appearance the windows use. No flag sets it; the file covers it.
        var appearanceMode: AppearanceMode = .system
        /// The three search-quality settings as one value. No flag sets
        /// them; the file covers them.
        var searchSettings = SearchSettings()
        /// How much diagnostics this run emits. `nil` leaves it to the file
        /// and the default. Never written back to the file.
        var logLevel: Logger.Level?
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
        /// One of the listed words, and nothing else. The list is the bound:
        /// a refusal reads it back, so neither can drift from the other.
        case allowedWords([String])

        /// The smallest value accepted. Words have no range; the zero keeps
        /// the switch total on a branch nothing reads, because words are
        /// matched rather than ranged.
        var minimum: Int {
            switch self {
            case .zeroOrMore: 0
            case .oneOrMore: 1
            case .allowedWords: 0
            }
        }

        /// That bound, in the words a refusal uses.
        var described: String {
            switch self {
            case .zeroOrMore: "zero or more"
            case .oneOrMore: "one or more"
            case let .allowedWords(words): "one of \(words.joined(separator: ", "))"
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

    /// Four words, and only those four. The list mirrors the words
    /// `Logger.Level/parse(word:)` reads: a word added there wants adding
    /// here, and the refusal below reads the list back so the two cannot
    /// drift apart unnoticed.
    static let logLevelFlag = Flag(
        name: "--log-level",
        accepts: .allowedWords(["error", "warning", "info", "debug"])
    )

    /// Every flag there is. Anything beginning with two dashes and absent from
    /// here is an unknown option, whatever else may name it.
    static let allFlags = [sampleCountFlag, stopMonitorEveryFlag, logLevelFlag]

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

        var description: String {
            switch self {
            case let .missingValue(flag):
                "\(flag.name) needs a value"
            case let .invalidValue(flag, value):
                switch flag.accepts {
                case .allowedWords:
                    // A word refusal names the words rather than a range:
                    // there is no bound to miss, only a list to leave.
                    "\"\(value)\" is not \(flag.accepts.described) (\(flag.name))"
                default:
                    "\"\(value)\" is not a whole number of \(flag.accepts.described) (\(flag.name))"
                }
            case let .unknownOption(option):
                "unknown option \"\(option)\""
            case let .duplicateFlag(flag):
                "\(flag.name) given more than once"
            }
        }
    }

    /// One line describing correct usage, for stderr.
    static let usage = "usage: Lanterna [\(sampleCountFlag.name) N]"
        + " [\(stopMonitorEveryFlag.name) SECONDS]"
        + " [\(logLevelFlag.name) LEVEL]"

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
        var values: [String: Int] = [:]
        var words: [String: String] = [:]
        var index = arguments.index(after: arguments.startIndex)

        while index < arguments.endIndex {
            let argument = arguments[index]
            if let flag = allFlags.first(where: { argument == $0.name }) {
                // Asked before the value is looked for, so a flag given twice
                // reads as a repeat whichever of the two is also malformed.
                guard values[flag.name] == nil, words[flag.name] == nil else {
                    throw .duplicateFlag(flag)
                }
                let valueIndex = arguments.index(after: index)
                guard valueIndex < arguments.endIndex else { throw .missingValue(flag) }
                try store(arguments[valueIndex], of: flag, values: &values, words: &words)
                index = arguments.index(after: valueIndex)
            } else if let flag = allFlags.first(where: { argument.hasPrefix($0.inlinePrefix) }) {
                let rawValue = String(argument.dropFirst(flag.inlinePrefix.count))
                try store(rawValue, of: flag, values: &values, words: &words)
                index = arguments.index(after: index)
            } else if argument.hasPrefix("--") {
                throw .unknownOption(argument)
            } else {
                index = arguments.index(after: index)
            }
        }

        return Options(
            sampleCount: values[sampleCountFlag.name],
            stopMonitorEvery: values[stopMonitorEveryFlag.name].map { .seconds($0) },
            logLevel: words[logLevelFlag.name].flatMap(Logger.Level.parse(word:))
        )
    }

    /// Files one flag's raw value under its name. Words and numbers share
    /// the repeat rule, so the guard lives here rather than once per form.
    private static func store(
        _ rawValue: String,
        of flag: Flag,
        values: inout [String: Int],
        words: inout [String: String]
    ) throws(ParseError) {
        guard values[flag.name] == nil, words[flag.name] == nil else {
            throw .duplicateFlag(flag)
        }
        switch flag.accepts {
        case .allowedWords:
            words[flag.name] = try parsedWord(rawValue, of: flag)
        default:
            values[flag.name] = try parsedValue(rawValue, of: flag)
        }
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

    /// One of the flag's words, and nothing else. Only exact words count:
    /// case, spacing and aliases refuse the way out-of-range numbers do.
    private static func parsedWord(
        _ rawValue: String,
        of flag: Flag
    ) throws(ParseError) -> String {
        guard case let .allowedWords(words) = flag.accepts, words.contains(rawValue) else {
            throw .invalidValue(flag: flag, value: rawValue)
        }
        return rawValue
    }
}
