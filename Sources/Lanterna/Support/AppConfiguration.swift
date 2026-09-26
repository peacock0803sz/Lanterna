import Foundation

// Generated from ConfigSchema.pkl. Do not edit by hand; change the schema
// and regenerate instead, so the three (schema, types, scaffold) stay as one.
//
// The runtime never evaluates Pkl. This file carries the schema's shape,
// defaults and validation into Swift, where the strictness lives.

/// The known keys of the config file, and nothing else.
///
/// A file holding any other key is invalid as a whole (FR-005). The check is
/// written out rather than derived from a `Decodable` struct because decoding
/// ignores unknown keys, which would silently accept them.
enum AppConfiguration {
    /// The schema generation this build understands.
    static let currentVersion = 1

    /// Every key there is. Anything else in the file is an unknown key.
    static let knownKeys: Set<String> = ["version", "sampleCount", "stopMonitorEvery"]

    /// The scaffold written when no file exists (FR-012).
    ///
    /// Absent keys mean their defaults, so the scaffold holds the version
    /// alone. Generated from the schema's defaults.
    static let scaffoldJSON = "{\n  \"version\": 1\n}\n"
}

/// The validated contents of the config file.
///
/// `nil` fields mean absent, which means the long-standing behaviour:
/// live windows for `sampleCount`, an ordinary run for `stopMonitorEvery`.
struct ValidConfiguration: Equatable, Sendable {
    var version: Int
    var sampleCount: Int?
    var stopMonitorEverySeconds: Int?
}

/// Why a file could not be used. The text after each case is the reason
/// alone, for the `config invalid (<reason>)` diagnostics line.
enum ConfigDecodeError: Error, Equatable, Sendable {
    case notJSONObject
    case emptyFile
    case invalidVersion(String)
    case newerVersion(Int)
    case unknownKey(String)
    case invalidValue(key: String)

    var reason: String {
        switch self {
        case .notJSONObject:
            "not a JSON object"
        case .emptyFile:
            "file is empty"
        case let .invalidVersion(raw):
            "invalid version \(raw)"
        case let .newerVersion(found):
            "version \(found) is newer than \(AppConfiguration.currentVersion)"
        case let .unknownKey(key):
            "unknown key \"\(key)\""
        case let .invalidValue(key):
            "\(key) is not a valid value"
        }
    }
}

/// What decoding found, including whether the version was assumed.
struct DecodedConfiguration: Equatable, Sendable {
    var config: ValidConfiguration
    /// True when the file held no version and 1 was assumed (R4).
    var assumedVersion: Bool
}

extension AppConfiguration {
    /// Reads the file's bytes into validated settings.
    ///
    /// A pure function over bytes so every accepted and rejected shape is
    /// unit-testable, the way `LaunchArguments.parse` is over arguments.
    /// Anything outside the schema invalidates the whole file (FR-004);
    /// there is no per-key recovery.
    static func decode(_ data: Data) -> Result<DecodedConfiguration, ConfigDecodeError> {
        let dict: [String: Any]
        switch parseObject(data) {
        case let .success(parsed):
            dict = parsed
        case let .failure(error):
            return .failure(error)
        }
        let version: Int
        let assumed: Bool
        switch checkedVersion(dict) {
        case let .success(found):
            (version, assumed) = found
        case let .failure(error):
            return .failure(error)
        }
        let sampleCount: Int?
        switch checkedOptionalInt(dict, key: "sampleCount", minimum: 0) {
        case let .success(found):
            sampleCount = found
        case let .failure(error):
            return .failure(error)
        }
        let stopMonitorEvery: Int?
        switch checkedOptionalInt(dict, key: "stopMonitorEvery", minimum: 1) {
        case let .success(found):
            stopMonitorEvery = found
        case let .failure(error):
            return .failure(error)
        }
        return .success(
            DecodedConfiguration(
                config: ValidConfiguration(
                    version: version,
                    sampleCount: sampleCount,
                    stopMonitorEverySeconds: stopMonitorEvery
                ),
                assumedVersion: assumed
            )
        )
    }

    /// The values this run uses. The command line wins where it says
    /// anything; the file covers the rest (FR-010). The command line never
    /// reaches the file.
    static func effectiveOptions(
        file: ValidConfiguration,
        cli: LaunchArguments.Options
    ) -> LaunchArguments.Options {
        LaunchArguments.Options(
            sampleCount: cli.sampleCount ?? file.sampleCount,
            stopMonitorEvery: cli.stopMonitorEvery
                ?? file.stopMonitorEverySeconds.map { .seconds($0) }
        )
    }

    /// Where the file lives under the given Application Support directory.
    ///
    /// The directory is a parameter rather than read here, so tests pass a
    /// temporary one and only `main.swift` resolves the real one (R8).
    static func configFileURL(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent("Lanterna", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    /// Writes the scaffold. Only for files that do not exist (FR-012);
    /// callers check first, because existing files are never touched (FR-013).
    static func writeScaffold(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(scaffoldJSON.utf8).write(to: url, options: .atomic)
    }

    /// Parses bytes into a JSON object, refusing anything else.
    private static func parseObject(_ data: Data) -> Result<[String: Any], ConfigDecodeError> {
        guard !data.isEmpty else { return .failure(.emptyFile) }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .failure(.notJSONObject)
        }
        guard let dict = raw as? [String: Any] else { return .failure(.notJSONObject) }
        for key in dict.keys where !knownKeys.contains(key) {
            return .failure(.unknownKey(key))
        }
        return .success(dict)
    }

    /// Reads the version, assuming 1 when absent (R4).
    private static func checkedVersion(_ dict: [String: Any]) -> Result<(Int, Bool), ConfigDecodeError> {
        guard let rawVersion = dict["version"] else { return .success((currentVersion, true)) }
        guard let version = jsonInt(rawVersion) else {
            return .failure(.invalidVersion("\(rawVersion)"))
        }
        guard version <= currentVersion else { return .failure(.newerVersion(version)) }
        return .success((version, false))
    }

    /// Reads one optional integer key with its lower bound.
    private static func checkedOptionalInt(
        _ dict: [String: Any],
        key: String,
        minimum: Int
    ) -> Result<Int?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let value = jsonInt(rawValue), value >= minimum else {
            return .failure(.invalidValue(key: key))
        }
        return .success(value)
    }

    /// A JSON integer and nothing else.
    ///
    /// Booleans are refused explicitly: without that, a boolean would pass
    /// through number bridging and read as 0 or 1.
    private static func jsonInt(_ value: Any) -> Int? {
        if value is Bool {
            return nil
        }
        return value as? Int
    }
}
