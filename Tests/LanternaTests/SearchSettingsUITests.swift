import Foundation
@testable import Lanterna
import Testing

/// The search settings through a restart, in the settings editor's shape.
///
/// Saving itself is covered by `SettingsSaveTests`; what lives here is the
/// round trip a restart performs for the three search keys: whatever the
/// editor offers must read back as the same values.
struct SearchSettingsUITests {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("config.json", isDirectory: false)
    }

    @Test func editedSearchSettingsReadBackUnchanged() throws {
        let url = try temporaryFile()
        var values = SettingsValues.defaults
        values.shortcutMemoryLength = 1
        values.fuzzyMatchEnabled = false
        values.resultOrder = .score
        let config = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        #expect(SettingsSaver.save(config, to: url, replacingInvalidFile: false) == .saved)
        let decoded = try #require(AppConfiguration.decode(Data(contentsOf: url)).successValue)
        let reread = SettingsValues.effective(from: decoded.config)
        #expect(reread.shortcutMemoryLength == 1)
        #expect(reread.fuzzyMatchEnabled == false)
        #expect(reread.resultOrder == .score)
    }

    @Test func defaultSearchSettingsReadBackAsDefaults() throws {
        let url = try temporaryFile()
        let values = SettingsValues.defaults
        let config = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        #expect(SettingsSaver.save(config, to: url, replacingInvalidFile: false) == .saved)
        let decoded = try #require(AppConfiguration.decode(Data(contentsOf: url)).successValue)
        let reread = SettingsValues.effective(from: decoded.config)
        #expect(reread.shortcutMemoryLength == 5)
        #expect(reread.fuzzyMatchEnabled == true)
        #expect(reread.resultOrder == .mru)
    }
}
