import Foundation
@testable import Lanterna
import Testing

/// The exclusions key on its own: shape, absence, and whole-file refusal.
///
/// Element-level forgiveness (empty fields, unreadable patterns) is pinned
/// in the matching suite's compile cases; what lives here is only whether
/// the file as a whole stands or falls.
struct ExclusionConfigTests {
    private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
        AppConfiguration.decode(Data(text.utf8))
    }

    @Test func exclusionsAreAbsentByDefault() throws {
        let decoded = try #require(decode("{\"version\": 1}").successValue)
        #expect(decoded.config.exclusions == nil)
    }

    @Test func exclusionsDecodeWhenPresent() throws {
        let decoded = try #require(decode("""
        {"version": 1, "exclusions": [
          {"app": "com.1password.1password", "titlePattern": "^Mini$"},
          {"app": "Installer", "titlePattern": "progress"}
        ]}
        """).successValue)
        #expect(decoded.config.exclusions == [
            ExclusionEntry(app: "com.1password.1password", titlePattern: "^Mini$"),
            ExclusionEntry(app: "Installer", titlePattern: "progress"),
        ])
    }

    @Test func nonArrayExclusionsInvalidateTheWholeFile() {
        let cases: [(String, ConfigDecodeError)] = [
            ("{\"version\": 1, \"exclusions\": \"abc\"}", .invalidValue(key: "exclusions")),
            ("{\"version\": 1, \"exclusions\": {}}", .invalidValue(key: "exclusions")),
            ("{\"version\": 1, \"exclusions\": true}", .invalidValue(key: "exclusions")),
        ]
        for (text, expected) in cases {
            #expect(decode(text).failureValue == expected, "for \(text)")
        }
    }

    @Test func misshapenElementsInvalidateTheWholeFile() {
        let cases: [(String, ConfigDecodeError)] = [
            ("{\"version\": 1, \"exclusions\": [{\"app\": \"x\"}]}", .invalidValue(key: "exclusions")),
            (
                "{\"version\": 1, \"exclusions\": [{\"titlePattern\": \"x\"}]}",
                .invalidValue(key: "exclusions")
            ),
            ("{\"version\": 1, \"exclusions\": [{\"app\": 1, \"titlePattern\": \"x\"}]}",
             .invalidValue(key: "exclusions")),
            ("{\"version\": 1, \"exclusions\": [\"abc\"]}", .invalidValue(key: "exclusions")),
        ]
        for (text, expected) in cases {
            #expect(decode(text).failureValue == expected, "for \(text)")
        }
    }

    @Test func invalidEntriesAreSkippedOneByOne() {
        let entries = [
            ExclusionEntry(app: "", titlePattern: "x"),
            ExclusionEntry(app: "x", titlePattern: ""),
            ExclusionEntry(app: "([", titlePattern: "x"),
            ExclusionEntry(app: "com.example.aid", titlePattern: "Mini"),
        ]
        let compiled = WindowExclusion.compile(entries)
        #expect(compiled.invalid == 3)
        #expect(compiled.rules.count == 1)
        #expect(compiled.rules[0].app == "com.example.aid")
    }

    @Test func exclusionsRoundTripThroughEncoding() throws {
        let decoded = try #require(decode("""
        {"version": 1, "exclusions": [{"app": "a.*", "titlePattern": "^b$"}]}
        """).successValue)
        let encoded = AppConfiguration.encode(decoded.config)
        let roundTripped = try #require(AppConfiguration.decode(encoded).successValue)
        #expect(roundTripped.config.exclusions == decoded.config.exclusions)
    }
}
