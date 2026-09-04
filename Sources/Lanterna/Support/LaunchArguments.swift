import Foundation

/// The command-line options the app understands.
///
/// Parsing is a pure function over an argument array rather than a read of
/// `ProcessInfo`, so every accepted and rejected form is unit-testable.
enum LaunchArguments {
    /// Why an argument could not be turned into a sample count.
    enum ParseError: Error, Equatable {
        case missingValue
        case invalidValue(String)

        /// One line describing correct usage, for stderr.
        var usage: String {
            switch self {
            case .missingValue:
                "usage: Lanterna [\(sampleCountFlag) N] — \(sampleCountFlag) needs a value"
            case let .invalidValue(value):
                "usage: Lanterna [\(sampleCountFlag) N] — "
                    + "\"\(value)\" is not a whole number of zero or more"
            }
        }
    }

    static let sampleCountFlag = "--sample-count"

    /// Number of fixture entries requested on the command line, or `nil` when
    /// the flag is absent. Both `--sample-count N` and `--sample-count=N` are
    /// accepted; anything else about the flag is a usage error, so a typo
    /// cannot silently fall back to the standard fixture.
    static func sampleCount(from arguments: [String]) throws(ParseError) -> Int? {
        let inlinePrefix = sampleCountFlag + "="
        guard let flagIndex = arguments.firstIndex(where: {
            $0 == sampleCountFlag || $0.hasPrefix(inlinePrefix)
        }) else {
            return nil
        }

        let argument = arguments[flagIndex]
        let rawValue: String
        if argument == sampleCountFlag {
            let valueIndex = arguments.index(after: flagIndex)
            guard valueIndex < arguments.endIndex else {
                throw .missingValue
            }
            rawValue = arguments[valueIndex]
        } else {
            rawValue = String(argument.dropFirst(inlinePrefix.count))
        }

        guard let count = Int(rawValue), count >= 0 else {
            throw .invalidValue(rawValue)
        }
        return count
    }
}
