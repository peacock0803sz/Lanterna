import Foundation

/// The command-line options the app understands.
///
/// Parsing is a pure function over an argument array rather than a read of
/// `ProcessInfo`, so every accepted and rejected form is unit-testable.
enum LaunchArguments {
    /// Why an argument could not be turned into a sample count. The text is the
    /// reason alone; the usage line is `LaunchArguments.usage`.
    enum ParseError: Error, Equatable, CustomStringConvertible {
        case missingValue
        case invalidValue(String)
        case unknownOption(String)
        case duplicateFlag

        var description: String {
            switch self {
            case .missingValue:
                "\(LaunchArguments.sampleCountFlag) needs a value"
            case let .invalidValue(value):
                "\"\(value)\" is not a whole number of zero or more"
            case let .unknownOption(option):
                "unknown option \"\(option)\""
            case .duplicateFlag:
                "\(LaunchArguments.sampleCountFlag) given more than once"
            }
        }
    }

    static let sampleCountFlag = "--sample-count"

    /// One line describing correct usage, for stderr.
    static let usage = "usage: Lanterna [\(sampleCountFlag) N]"

    /// Number of fixture entries requested on the command line, or `nil` when
    /// the flag is absent. Both `--sample-count N` and `--sample-count=N` are
    /// accepted, in any position. A missing or malformed value, an unknown
    /// `--` option and a repeated flag are all rejected, so a typo cannot
    /// silently fall back to the standard fixture.
    ///
    /// Single-dash arguments are ignored: macOS and Xcode inject their own,
    /// such as `-NSDocumentRevisionsDebugMode YES`.
    static func sampleCount(from arguments: [String]) throws(ParseError) -> Int? {
        let inlinePrefix = sampleCountFlag + "="
        var count: Int?
        var index = arguments.index(after: arguments.startIndex)

        while index < arguments.endIndex {
            let argument = arguments[index]
            if argument == sampleCountFlag {
                guard count == nil else {
                    throw .duplicateFlag
                }
                let valueIndex = arguments.index(after: index)
                guard valueIndex < arguments.endIndex else {
                    throw .missingValue
                }
                count = try parsedCount(arguments[valueIndex])
                index = arguments.index(after: valueIndex)
            } else if argument.hasPrefix(inlinePrefix) {
                guard count == nil else {
                    throw .duplicateFlag
                }
                count = try parsedCount(String(argument.dropFirst(inlinePrefix.count)))
                index = arguments.index(after: index)
            } else if argument.hasPrefix("--") {
                throw .unknownOption(argument)
            } else {
                index = arguments.index(after: index)
            }
        }
        return count
    }

    private static func parsedCount(_ rawValue: String) throws(ParseError) -> Int {
        guard let count = Int(rawValue), count >= 0 else {
            throw .invalidValue(rawValue)
        }
        return count
    }
}
