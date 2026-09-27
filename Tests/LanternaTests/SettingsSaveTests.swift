import Foundation
@testable import Lanterna
import Testing

/// What the save path does with whatever it finds on disk.
///
/// The settings themselves are covered by `ConfigEncodingTests`; these
/// cover the decision around them: create when missing, confirm before
/// throwing away an invalid file, and never lose the live values on a
/// failure.
struct SettingsSaveTests {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("config.json", isDirectory: false)
    }

    private func minimalConfig() -> ValidConfiguration {
        ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    }

    @Test func missingFileIsCreated() throws {
        let url = try temporaryFile()
        #expect(SettingsSaver.save(minimalConfig(), to: url, replacingInvalidFile: false) == .saved)
        let data = try Data(contentsOf: url)
        #expect(AppConfiguration.decode(data).successValue?.config == minimalConfig())
    }

    @Test func validFileIsOverwritten() throws {
        let url = try temporaryFile()
        try Data(AppConfiguration.scaffoldJSON.utf8).write(to: url)
        var config = minimalConfig()
        config.appearanceMode = .dark
        #expect(SettingsSaver.save(config, to: url, replacingInvalidFile: false) == .saved)
        let data = try Data(contentsOf: url)
        #expect(AppConfiguration.decode(data).successValue?.config == config)
    }

    @Test func invalidFileNeedsConfirmationFirst() throws {
        let url = try temporaryFile()
        try Data("not json".utf8).write(to: url)
        #expect(
            SettingsSaver.save(minimalConfig(), to: url, replacingInvalidFile: false)
                == .needsConfirmation
        )
        #expect(try String(contentsOf: url, encoding: .utf8) == "not json")
    }

    @Test func invalidFileIsReplacedWithApproval() throws {
        let url = try temporaryFile()
        try Data("not json".utf8).write(to: url)
        #expect(
            SettingsSaver.save(minimalConfig(), to: url, replacingInvalidFile: true) == .saved
        )
        let data = try Data(contentsOf: url)
        #expect(AppConfiguration.decode(data).successValue?.config == minimalConfig())
    }

    @Test func unwritableDestinationFails() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("blocker", isDirectory: false)
        try Data("x".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent("config.json", isDirectory: false)
        #expect(
            SettingsSaver.save(minimalConfig(), to: url, replacingInvalidFile: false)
                == .failed(reason: "cannot write file")
        )
    }
}
