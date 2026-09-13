import Foundation

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
    }

    /// One flag, and what it will take.
    ///
    /// The bound and the words for it sit together because a refusal has to
    /// say which range was missed. Naming the flag but not its range would
    /// leave a reader knowing which value was rejected and not what would have
    /// been accepted instead.
    struct Flag: Equatable, Sendable {
        let name: String
        /// The smallest value accepted.
        let minimum: Int
        /// That bound, in the words a refusal uses.
        let acceptedRange: String

        /// What the `--flag=value` form starts with.
        var inlinePrefix: String {
            name + "="
        }
    }

    static let sampleCountFlag = Flag(
        name: "--sample-count",
        minimum: 0,
        acceptedRange: "zero or more"
    )

    /// Whole seconds, and at least one of them. A period of zero would be a
    /// request to stop the monitor as fast as the loop can be asked to, which
    /// is a way of turning it off rather than a way of watching it recover.
    static let stopMonitorEveryFlag = Flag(
        name: "--stop-monitor-every",
        minimum: 1,
        acceptedRange: "one or more"
    )

    /// Every flag there is. Anything beginning with two dashes and absent from
    /// here is an unknown option, whatever else may name it.
    static let allFlags = [sampleCountFlag, stopMonitorEveryFlag]

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
                "\"\(value)\" is not a whole number of \(flag.acceptedRange) (\(flag.name))"
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
        var index = arguments.index(after: arguments.startIndex)

        while index < arguments.endIndex {
            let argument = arguments[index]
            if let flag = allFlags.first(where: { argument == $0.name }) {
                // Asked before the value is looked for, so a flag given twice
                // reads as a repeat whichever of the two is also malformed.
                guard values[flag.name] == nil else { throw .duplicateFlag(flag) }
                let valueIndex = arguments.index(after: index)
                guard valueIndex < arguments.endIndex else { throw .missingValue(flag) }
                values[flag.name] = try parsedValue(arguments[valueIndex], of: flag)
                index = arguments.index(after: valueIndex)
            } else if let flag = allFlags.first(where: { argument.hasPrefix($0.inlinePrefix) }) {
                guard values[flag.name] == nil else { throw .duplicateFlag(flag) }
                let rawValue = String(argument.dropFirst(flag.inlinePrefix.count))
                values[flag.name] = try parsedValue(rawValue, of: flag)
                index = arguments.index(after: index)
            } else if argument.hasPrefix("--") {
                throw .unknownOption(argument)
            } else {
                index = arguments.index(after: index)
            }
        }

        return Options(
            sampleCount: values[sampleCountFlag.name],
            stopMonitorEvery: values[stopMonitorEveryFlag.name].map { .seconds($0) }
        )
    }

    private static func parsedValue(
        _ rawValue: String,
        of flag: Flag
    ) throws(ParseError) -> Int {
        guard let value = Int(rawValue), value >= flag.minimum else {
            throw .invalidValue(flag: flag, value: rawValue)
        }
        return value
    }
}
