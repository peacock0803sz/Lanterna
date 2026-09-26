import Foundation
@testable import Lanterna
import Testing

struct ConfigStoreTests {
    private static func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
        AppConfiguration.decode(Data(text.utf8))
    }

    private static func tempDirectory() throws -> URL {
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

    @Test func scaffoldWritesDefaults() throws {
        let base = try tempDirectory()
        let url = AppConfiguration.configFileURL(applicationSupport: base)
        try AppConfiguration.writeScaffold(to: url)
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == AppConfiguration.scaffoldJSON)
        let decoded = try #require(AppConfiguration.decode(Data(written.utf8)).successValue)
        #expect(decoded.config == ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil))
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
