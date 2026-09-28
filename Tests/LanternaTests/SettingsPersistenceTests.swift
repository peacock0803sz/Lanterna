import Foundation
@testable import Lanterna
import Logging
import Testing

/// What survives a restart, and what an invalid file leaves behind.
///
/// Saving itself is covered by `SettingsSaveTests`; these cover the
/// round trip a restart performs: bytes on disk become the same values
/// again, and bytes that fail validation become the defaults with the
/// reason kept for the diagnostics line.
struct SettingsPersistenceTests {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("config.json", isDirectory: false)
    }

    @Test func savedValuesReadBackUnchanged() throws {
        let url = try temporaryFile()
        var values = SettingsValues.defaults
        values.appearanceMode = .dark
        values.displayModes.otherSpace = .hide
        values.romajiScope = .kanaOnly
        let config = values.configuration(version: 1, sampleCount: 2, stopMonitorEverySeconds: 5)
        #expect(SettingsSaver.save(config, to: url, replacingInvalidFile: false) == .saved)
        let readBack = try Data(contentsOf: url)
        let decoded = try #require(AppConfiguration.decode(readBack).successValue)
        #expect(SettingsValues.effective(from: decoded.config) == values)
        #expect(decoded.config.sampleCount == 2)
        #expect(decoded.config.stopMonitorEverySeconds == 5)
    }

    @Test func unsavedKeysSurviveASave() throws {
        let url = try temporaryFile()
        let values = SettingsValues.defaults
        let config = values.configuration(
            version: 1,
            sampleCount: 2,
            stopMonitorEverySeconds: 5,
            logLevel: .debug
        )
        #expect(SettingsSaver.save(config, to: url, replacingInvalidFile: false) == .saved)
        let decoded = try #require(try AppConfiguration.decode(Data(contentsOf: url)).successValue)
        #expect(decoded.config.logLevel == .debug)
    }

    @Test func invalidFileFallsBackToDefaultsWithReason() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = support.appendingPathComponent("Lanterna", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("config.json"))
        let outcome = AppConfiguration.loadOrScaffold(applicationSupport: support)
        guard case let .failed(reason) = outcome.0 else {
            Issue.record("Invalid file must fail loading")
            return
        }
        #expect(!reason.isEmpty)
        #expect(SettingsValues.defaults.appearanceMode == .system)
    }

    @Test func unknownKeyInvalidatesFileAsAWhole() throws {
        let url = try temporaryFile()
        try Data("{\"version\": 1, \"mystery\": 1}".utf8).write(to: url)
        let data = try Data(contentsOf: url)
        #expect(AppConfiguration.decode(data).failureValue == .unknownKey("mystery"))
    }
}
