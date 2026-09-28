import Foundation
@testable import Lanterna
import Testing

/// The exclusion list through a restart, and what the editor may offer.
///
/// Saving itself is covered by `SettingsSaveTests`; what lives here is the
/// round trip a restart performs for exclusions, and the validity rule the
/// settings editor shows before anything is saved.
struct ExclusionSettingsUITests {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("config.json", isDirectory: false)
    }

    @Test func editedExclusionsReadBackUnchanged() throws {
        let url = try temporaryFile()
        var values = SettingsValues.defaults
        values.exclusions = [
            ExclusionEntry(app: "com.1password.1password", titlePattern: "^Mini$"),
            ExclusionEntry(app: "Installer", titlePattern: "progress"),
        ]
        let config = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        #expect(SettingsSaver.save(config, to: url, replacingInvalidFile: false) == .saved)
        let decoded = try #require(AppConfiguration.decode(Data(contentsOf: url)).successValue)
        #expect(SettingsValues.effective(from: decoded.config).exclusions == values.exclusions)
    }

    @Test func removedExclusionsStayRemoved() throws {
        let url = try temporaryFile()
        var values = SettingsValues.defaults
        values.exclusions = [ExclusionEntry(app: "a", titlePattern: "b")]
        let saved = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        #expect(SettingsSaver.save(saved, to: url, replacingInvalidFile: false) == .saved)
        values.exclusions = []
        let cleared = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        #expect(SettingsSaver.save(cleared, to: url, replacingInvalidFile: false) == .saved)
        let decoded = try #require(AppConfiguration.decode(Data(contentsOf: url)).successValue)
        #expect(decoded.config.exclusions == nil)
        #expect(SettingsValues.effective(from: decoded.config).exclusions == [])
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("exclusions"))
    }

    @Test func validityRuleMarksWhatTheEditorFlags() {
        #expect(WindowExclusion.isValid(app: "Safari", titlePattern: "x"))
        #expect(WindowExclusion.isValid(app: "Safari.*", titlePattern: "^x$"))
        #expect(!WindowExclusion.isValid(app: "", titlePattern: "x"))
        #expect(!WindowExclusion.isValid(app: "Safari", titlePattern: ""))
        #expect(!WindowExclusion.isValid(app: "([", titlePattern: "x"))
    }
}
