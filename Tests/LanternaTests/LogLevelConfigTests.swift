import Foundation
@testable import Lanterna
import Logging
import Testing

/// The log-level key on its own, split out the way `ConfigStoreTests` splits
/// long suites: that file reached the body-length limit, so the three tests
/// pinning this key live here instead.
struct LogLevelConfigTests {
    private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
        AppConfiguration.decode(Data(text.utf8))
    }

    @Test func logLevelIsAbsentByDefault() throws {
        let decoded = try #require(decode("{\"version\": 1}").successValue)
        #expect(decoded.config.logLevel == nil)
        #expect(Logger.Level.effective(cli: nil, file: decoded.config.logLevel) == .warning)
    }

    @Test func logLevelDecodesWhenPresent() throws {
        for word in ["error", "warning", "info", "debug"] {
            let decoded = try #require(
                decode("{\"version\": 1, \"logLevel\": \"\(word)\"}").successValue
            )
            #expect(decoded.config.logLevel?.rawValue == word)
        }
    }

    @Test func invalidLogLevelFallsBackAsAWhole() {
        let cases: [(String, ConfigDecodeError)] = [
            ("{\"version\": 1, \"logLevel\": \"WARN\"}", .invalidValue(key: "logLevel")),
            ("{\"version\": 1, \"logLevel\": \"warn\"}", .invalidValue(key: "logLevel")),
            ("{\"version\": 1, \"logLevel\": \"verbose\"}", .invalidValue(key: "logLevel")),
            ("{\"version\": 1, \"logLevel\": \" info\"}", .invalidValue(key: "logLevel")),
            ("{\"version\": 1, \"logLevel\": true}", .invalidValue(key: "logLevel")),
            ("{\"version\": 1, \"logLevel\": 1}", .invalidValue(key: "logLevel")),
        ]
        for (text, expected) in cases {
            #expect(decode(text).failureValue == expected, "for \(text)")
        }
    }
}
