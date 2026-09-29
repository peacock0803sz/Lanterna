import Foundation
@testable import Lanterna
import Testing

struct TextScaleConfigTests {
    private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
        AppConfiguration.decode(Data(text.utf8))
    }

    @Test func textScaleIsAbsentByDefault() throws {
        let decoded = try #require(decode("{\"version\": 1}").successValue)
        #expect(decoded.config.textScale == nil)
        #expect(decoded.textScaleIssue == nil)
        #expect(TextScaleLevel.effective(from: decoded.config) == .standard)
    }

    @Test func textScaleDecodesEachStep() throws {
        let cases: [(String, TextScaleLevel)] = [
            ("0.85", .small), ("0.93", .smallMedium), ("1.0", .standard),
            ("1.12", .largeMedium), ("1.25", .large),
        ]
        for (text, level) in cases {
            let decoded = try #require(
                decode("{\"version\": 1, \"textScale\": \(text)}").successValue
            )
            #expect(decoded.textScaleIssue == nil, "for \(text)")
            #expect(TextScaleLevel.effective(from: decoded.config) == level, "for \(text)")
        }
    }

    @Test func integerOneMatchesOnePointOh() throws {
        let decoded = try #require(decode("{\"version\": 1, \"textScale\": 1}").successValue)
        #expect(decoded.textScaleIssue == nil)
        #expect(TextScaleLevel.effective(from: decoded.config) == .standard)
    }

    @Test func offStepValueFallsBackWithANote() throws {
        let decoded = try #require(decode("{\"version\": 1, \"textScale\": 2.0}").successValue)
        #expect(decoded.config.textScale == nil)
        #expect(decoded.textScaleIssue != nil)
        #expect(TextScaleLevel.effective(from: decoded.config) == .standard)
    }

    @Test func nonNumericValueFallsBackWithANote() throws {
        for text in [
            "{\"version\": 1, \"textScale\": \"large\"}",
            "{\"version\": 1, \"textScale\": true}",
            "{\"version\": 1, \"textScale\": [1.0]}",
        ] {
            let decoded = try #require(decode(text).successValue)
            #expect(decoded.config.textScale == nil, "for \(text)")
            #expect(decoded.textScaleIssue != nil, "for \(text)")
            #expect(TextScaleLevel.effective(from: decoded.config) == .standard)
        }
    }

    /// False, an object and null are not numbers, so they fall back
    /// with a note instead of failing the file.
    @Test func falseEmptyObjectAndNullFallBackWithANote() throws {
        for text in [
            "{\"version\": 1, \"textScale\": false}",
            "{\"version\": 1, \"textScale\": {}}",
            "{\"version\": 1, \"textScale\": null}",
        ] {
            let decoded = try #require(decode(text).successValue)
            #expect(decoded.config.textScale == nil, "for \(text)")
            #expect(
                decoded.textScaleIssue == "textScale is not a valid value; using 1.0",
                "for \(text)"
            )
            #expect(TextScaleLevel.effective(from: decoded.config) == .standard, "for \(text)")
        }
    }

    /// An explicit standard step reads as absent, so saving omits it
    /// the way absent does.
    @Test func explicitStandardReadsAsAbsent() throws {
        for text in [
            "{\"version\": 1, \"textScale\": 1.0}",
            "{\"version\": 1, \"textScale\": 1}",
        ] {
            let decoded = try #require(decode(text).successValue)
            #expect(decoded.config.textScale == nil, "for \(text)")
            #expect(decoded.textScaleIssue == nil, "for \(text)")
            #expect(TextScaleLevel.effective(from: decoded.config) == .standard, "for \(text)")
        }
    }

    /// The fallback note keeps one wording, so the launch line stays stable.
    @Test func invalidValueReportsExactNote() throws {
        let decoded = try #require(decode("{\"version\": 1, \"textScale\": 2.0}").successValue)
        #expect(decoded.config.textScale == nil)
        #expect(decoded.textScaleIssue == "textScale is not a valid value; using 1.0")
        #expect(TextScaleLevel.effective(from: decoded.config) == .standard)
    }

    @Test func textScaleEncodesOnlyWhenSet() throws {
        var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        let bare = try #require(String(data: AppConfiguration.encode(config), encoding: .utf8))
        #expect(!bare.contains("textScale"))
        config.textScale = 1.12
        let encoded = try #require(String(data: AppConfiguration.encode(config), encoding: .utf8))
        #expect(encoded.contains("\"textScale\": 1.12"))
        let roundTripped = try #require(AppConfiguration.decode(Data(encoded.utf8)).successValue)
        #expect(roundTripped.config.textScale == 1.12)
        #expect(roundTripped.textScaleIssue == nil)
    }
}

extension TextScaleConfigTests {
    @Test func settingsRoundTripPreservesTheStep() {
        var values = SettingsValues.defaults
        values.textScale = .large
        let config = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        #expect(config.textScale == 1.25)
        #expect(TextScaleLevel.effective(from: config) == .large)
    }

    @Test func standardStepStaysAbsentOnSave() {
        let config = SettingsValues.defaults.configuration(
            version: 1, sampleCount: nil, stopMonitorEverySeconds: nil
        )
        #expect(config.textScale == nil)
    }
}
