import Foundation

// Mirrors ConfigSchema.pkl in Swift. Change the schema first, then mirror
// it here, and keep the three (schema, types, scaffold) as one. CI checks
// the schema's rendering against config/schema-snapshot.json, which is the
// mechanical part of the sync; the mirroring itself is by hand.
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
    static let knownKeys: Set<String> = [
        "version", "sampleCount", "stopMonitorEvery",
        "otherSpaceMode", "hiddenAppMode", "minimizedMode", "fullscreenMode",
    ]

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
    var otherSpaceMode: DisplayMode?
    var hiddenAppMode: DisplayMode?
    var minimizedMode: DisplayMode?
    var fullscreenMode: DisplayMode?

    init(
        version: Int,
        sampleCount: Int?,
        stopMonitorEverySeconds: Int?,
        otherSpaceMode: DisplayMode? = nil,
        hiddenAppMode: DisplayMode? = nil,
        minimizedMode: DisplayMode? = nil,
        fullscreenMode: DisplayMode? = nil
    ) {
        self.version = version
        self.sampleCount = sampleCount
        self.stopMonitorEverySeconds = stopMonitorEverySeconds
        self.otherSpaceMode = otherSpaceMode
        self.hiddenAppMode = hiddenAppMode
        self.minimizedMode = minimizedMode
        self.fullscreenMode = fullscreenMode
    }
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

// What the launch-time load found.

enum ConfigLoadOutcome: Equatable, Sendable {
    case loaded(DecodedConfiguration)
    case created
    case failed(reason: String)
}

extension AppConfiguration {
    /// Loads the file or scaffolds it when missing.
    ///
    /// The only place that touches the file besides the scaffold write:
    /// existing files are read and never written (FR-013). Returns the
    /// outcome with the file URL so callers can say where in diagnostics.
    static func loadOrScaffold(applicationSupport: URL) -> (ConfigLoadOutcome, URL) {
        let url = configFileURL(applicationSupport: applicationSupport)
        guard FileManager.default.fileExists(atPath: url.path) else {
            do {
                try writeScaffold(to: url)
                return (.created, url)
            } catch {
                return (.failed(reason: "cannot create file"), url)
            }
        }
        guard let data = try? Data(contentsOf: url) else {
            return (.failed(reason: "cannot read file"), url)
        }
        switch decode(data) {
        case let .success(decoded):
            return (.loaded(decoded), url)
        case let .failure(error):
            return (.failed(reason: error.reason), url)
        }
    }

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
        let stopMonitorEvery: Int?
        switch checkedCountOptions(dict) {
        case let .success(found):
            (sampleCount, stopMonitorEvery) = found
        case let .failure(error):
            return .failure(error)
        }
        switch checkedConfiguration(
            dict,
            version: version,
            sampleCount: sampleCount,
            stopMonitorEverySeconds: stopMonitorEvery
        ) {
        case let .success(config):
            return .success(DecodedConfiguration(config: config, assumedVersion: assumed))
        case let .failure(error):
            return .failure(error)
        }
    }

    /// The values this run uses. The command line wins where it says
    /// anything; the file covers the rest (FR-010). The command line never
    /// reaches the file. Display modes have no flag, so the file always
    /// covers them.
    static func effectiveOptions(
        file: ValidConfiguration,
        cli: LaunchArguments.Options
    ) -> LaunchArguments.Options {
        LaunchArguments.Options(
            sampleCount: cli.sampleCount ?? file.sampleCount,
            stopMonitorEvery: cli.stopMonitorEvery
                ?? file.stopMonitorEverySeconds.map { .seconds($0) },
            displayModes: DisplayModes.effective(from: file)
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
        // Sorted so the reported key is stable across runs.
        for key in dict.keys.sorted() where !knownKeys.contains(key) {
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

    /// Reads the two count keys together, so `decode` stays small.
    private static func checkedCountOptions(_ dict: [String: Any]) -> Result<
        (Int?, Int?), ConfigDecodeError
    > {
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
        return .success((sampleCount, stopMonitorEvery))
    }

    /// Assembles the validated configuration, reading the display modes last.
    private static func checkedConfiguration(
        _ dict: [String: Any],
        version: Int,
        sampleCount: Int?,
        stopMonitorEverySeconds: Int?
    ) -> Result<ValidConfiguration, ConfigDecodeError> {
        var config = ValidConfiguration(
            version: version,
            sampleCount: sampleCount,
            stopMonitorEverySeconds: stopMonitorEverySeconds
        )
        let keys: [(String, WritableKeyPath<ValidConfiguration, DisplayMode?>)] = [
            ("otherSpaceMode", \.otherSpaceMode),
            ("hiddenAppMode", \.hiddenAppMode),
            ("minimizedMode", \.minimizedMode),
            ("fullscreenMode", \.fullscreenMode),
        ]
        for (key, path) in keys {
            switch checkedOptionalMode(dict, key: key) {
            case let .success(found):
                config[keyPath: path] = found
            case let .failure(error):
                return .failure(error)
            }
        }
        return .success(config)
    }

    /// Reads one optional display-mode key. Anything but the three known
    /// words invalidates the whole file, like any other bad value.
    private static func checkedOptionalMode(
        _ dict: [String: Any],
        key: String
    ) -> Result<DisplayMode?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let text = rawValue as? String, let mode = DisplayMode(rawValue: text) else {
            return .failure(.invalidValue(key: key))
        }
        return .success(mode)
    }

    /// A JSON integer and nothing else.
    ///
    /// Booleans are refused by their Objective-C type: an `is Bool` check
    /// wrongly matches integer 1, so only the `c` type is turned away.
    private static func jsonInt(_ value: Any) -> Int? {
        if let number = value as? NSNumber, String(cString: number.objCType) == "c" {
            return nil
        }
        return value as? Int
    }
}
