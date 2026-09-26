import Foundation
@testable import Lanterna
import Testing

struct ConfigStoreTests {
    private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
        AppConfiguration.decode(Data(text.utf8))
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func minimalFileIsValid() throws {
        let decoded = try #require(decode("{\"version\": 1}").successValue)
        #expect(decoded.config == ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil))
        #expect(!decoded.assumedVersion)
    }

    @Test func fullFileIsValid() throws {
        let decoded = try #require(
            decode("{\"version\": 1, \"sampleCount\": 3, \"stopMonitorEvery\": 7}").successValue
        )
        #expect(decoded.config.sampleCount == 3)
        #expect(decoded.config.stopMonitorEverySeconds == 7)
        #expect(!decoded.assumedVersion)
    }

    @Test func missingVersionIsAssumed() throws {
        let decoded = try #require(decode("{\"sampleCount\": 3}").successValue)
        #expect(decoded.config.version == AppConfiguration.currentVersion)
        #expect(decoded.assumedVersion)
    }

    @Test func zeroCountIsValid() throws {
        let decoded = try #require(decode("{\"version\": 1, \"sampleCount\": 0}").successValue)
        #expect(decoded.config.sampleCount == 0)
    }

    @Test func commandLineWinsWhereItSaysAnything() throws {
        let file = ValidConfiguration(version: 1, sampleCount: 3, stopMonitorEverySeconds: 7)
        let cli = try LaunchArguments.parse(["Lanterna", "--sample-count", "5"])
        let effective = AppConfiguration.effectiveOptions(file: file, cli: cli)
        #expect(effective.sampleCount == 5)
        #expect(effective.stopMonitorEvery == .seconds(7))
    }

    @Test func fileCoversWhatTheCommandLineLeavesOut() throws {
        let file = ValidConfiguration(version: 1, sampleCount: 3, stopMonitorEverySeconds: 7)
        let cli = try LaunchArguments.parse(["Lanterna"])
        let effective = AppConfiguration.effectiveOptions(file: file, cli: cli)
        #expect(effective.sampleCount == 3)
        #expect(effective.stopMonitorEvery == .seconds(7))
    }

    /// The display modes come from the file, present keys winning and
    /// absent ones falling back to the defaults, whatever the command
    /// line says.
    @Test func displayModesComeFromTheFile() throws {
        let file = ValidConfiguration(
            version: 1,
            sampleCount: nil,
            stopMonitorEverySeconds: nil,
            hiddenAppMode: .show,
            fullscreenMode: .hide
        )
        let cli = try LaunchArguments.parse(["Lanterna", "--sample-count", "5"])
        let effective = AppConfiguration.effectiveOptions(file: file, cli: cli)
        #expect(
            effective.displayModes == DisplayModes(
                otherSpace: DisplayModes.defaults.otherSpace,
                hiddenApp: .show,
                minimized: DisplayModes.defaults.minimized,
                fullscreen: .hide
            )
        )
    }

    @Test func appearanceModeComesFromTheFile() throws {
        let file = ValidConfiguration(
            version: 1,
            sampleCount: nil,
            stopMonitorEverySeconds: nil,
            appearanceMode: .dark
        )
        let cli = try LaunchArguments.parse(["Lanterna", "--sample-count", "5"])
        let effective = AppConfiguration.effectiveOptions(file: file, cli: cli)
        #expect(effective.appearanceMode == .dark)
        #expect(effective.sampleCount == 5)
    }

    @Test func configFileURLLivesUnderLanterna() {
        let base = URL(fileURLWithPath: "/tmp/ConfigStoreTests", isDirectory: true)
        #expect(
            AppConfiguration.configFileURL(applicationSupport: base).path
                == "/tmp/ConfigStoreTests/Lanterna/config.json"
        )
    }

    @Test func unreadableShapesFallBackAsAWhole() {
        let cases: [(String, ConfigDecodeError)] = [
            ("", .emptyFile),
            ("{", .notJSONObject),
            ("[1, 2]", .notJSONObject),
            ("\"just a string\"", .notJSONObject),
            ("{\"version\": \"one\"}", .invalidVersion("one")),
            ("{\"version\": 2}", .newerVersion(2)),
            ("{\"version\": 1, \"filterMode\": \"x\"}", .unknownKey("filterMode")),
            ("{\"version\": 1, \"sampleCount\": -1}", .invalidValue(key: "sampleCount")),
            ("{\"version\": 1, \"sampleCount\": \"three\"}", .invalidValue(key: "sampleCount")),
            ("{\"version\": 1, \"sampleCount\": true}", .invalidValue(key: "sampleCount")),
            (
                "{\"version\": 1, \"sampleCount\": 3, \"stopMonitorEvery\": 0}",
                .invalidValue(key: "stopMonitorEvery")
            ),
        ]
        for (text, expected) in cases {
            #expect(decode(text).failureValue == expected, "for \(text)")
        }
    }

    @Test func reasonsMatchTheDiagnosticsContract() {
        #expect(ConfigDecodeError.notJSONObject.reason == "not a JSON object")
        #expect(ConfigDecodeError.emptyFile.reason == "file is empty")
        #expect(ConfigDecodeError.newerVersion(2).reason == "version 2 is newer than 1")
        #expect(ConfigDecodeError.unknownKey("filterMode").reason == "unknown key \"filterMode\"")
        #expect(
            ConfigDecodeError.invalidValue(key: "sampleCount").reason == "sampleCount is not a valid value"
        )
    }

    @Test func mruKeysAreRejectedAndNeverStored() throws {
        let error = try #require(decode("{\"version\": 1, \"mru\": []}").failureValue)
        #expect(error == .unknownKey("mru"))
    }

    @Test func existingFilesAreLeftUntouched() throws {
        let base = try tempDirectory()
        let url = AppConfiguration.configFileURL(applicationSupport: base)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = "{\"version\": 1, \"sampleCount\": 3}"
        try Data(original.utf8).write(to: url)
        let (outcome, found) = AppConfiguration.loadOrScaffold(applicationSupport: base)
        #expect(found == url)
        guard case let .loaded(decoded) = outcome else {
            Issue.record("expected loaded, found \(outcome)")
            return
        }
        #expect(decoded.config.sampleCount == 3)
        #expect(try String(contentsOf: url, encoding: .utf8) == original)
    }

    @Test func missingFilesAreScaffolded() throws {
        let base = try tempDirectory()
        let (outcome, url) = AppConfiguration.loadOrScaffold(applicationSupport: base)
        #expect(outcome == .created)
        #expect(try String(contentsOf: url, encoding: .utf8) == AppConfiguration.scaffoldJSON)
    }

    @Test func scaffoldWritesDefaults() throws {
        let base = try tempDirectory()
        let url = AppConfiguration.configFileURL(applicationSupport: base)
        try AppConfiguration.writeScaffold(to: url)
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == AppConfiguration.scaffoldJSON)
        let decoded = try #require(AppConfiguration.decode(Data(written.utf8)).successValue)
        #expect(decoded.config == ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil))
    }

    @Test func displayModesAreAbsentByDefault() throws {
        let decoded = try #require(decode("{\"version\": 1}").successValue)
        #expect(decoded.config.otherSpaceMode == nil)
        #expect(decoded.config.hiddenAppMode == nil)
        #expect(decoded.config.minimizedMode == nil)
        #expect(decoded.config.fullscreenMode == nil)
    }

    @Test func displayModesDecodeWhenPresent() throws {
        let decoded = try #require(
            decode(
                "{\"version\": 1, \"otherSpaceMode\": \"hide\", "
                    + "\"hiddenAppMode\": \"show\", \"minimizedMode\": \"separateAtBottom\", "
                    + "\"fullscreenMode\": \"hide\"}"
            ).successValue
        )
        #expect(decoded.config.otherSpaceMode == .hide)
        #expect(decoded.config.hiddenAppMode == .show)
        #expect(decoded.config.minimizedMode == .separateAtBottom)
        #expect(decoded.config.fullscreenMode == .hide)
    }

    @Test func partialDisplayModesAreValid() throws {
        let decoded = try #require(
            decode("{\"version\": 1, \"minimizedMode\": \"hide\"}").successValue
        )
        #expect(decoded.config.minimizedMode == .hide)
        #expect(decoded.config.otherSpaceMode == nil)
    }

    @Test func invalidDisplayModesFallBackAsAWhole() {
        let cases: [(String, ConfigDecodeError)] = [
            ("{\"version\": 1, \"minimizedMode\": \"HIDE\"}", .invalidValue(key: "minimizedMode")),
            ("{\"version\": 1, \"minimizedMode\": \"separate-at-bottom\"}", .invalidValue(key: "minimizedMode")),
            ("{\"version\": 1, \"minimizedMode\": 1}", .invalidValue(key: "minimizedMode")),
            ("{\"version\": 1, \"minimizedMode\": true}", .invalidValue(key: "minimizedMode")),
            ("{\"version\": 1, \"otherSpaceMode\": \"hide\", \"mysteryMode\": \"show\"}", .unknownKey("mysteryMode")),
        ]
        for (text, expected) in cases {
            #expect(decode(text).failureValue == expected, "for \(text)")
        }
    }

    @Test func absentDisplayModesMeanDefaults() {
        let config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        let modes = DisplayModes.effective(from: config)
        #expect(modes == DisplayModes.defaults)
    }

    @Test func presentDisplayModesOverrideDefaults() {
        var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        config.minimizedMode = .hide
        config.fullscreenMode = .separateAtBottom
        let modes = DisplayModes.effective(from: config)
        #expect(modes.minimized == .hide)
        #expect(modes.fullscreen == .separateAtBottom)
        #expect(modes.otherSpace == .show)
        #expect(modes.hiddenApp == .separateAtBottom)
    }
}

extension Result where Failure == ConfigDecodeError {
    var successValue: Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }

    var failureValue: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}
