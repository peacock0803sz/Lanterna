import Foundation

/// Encoding side of the config file, split out when the decoding file
/// reached the file-length limit. Decoding stays in `AppConfiguration`;
/// everything that writes lives here.
extension AppConfiguration {
    /// Encodes validated settings into the file's canonical form.
    ///
    /// Sorted keys, two-space indent, trailing newline, matching the
    /// scaffold's shape. Absent values are omitted, so a configuration
    /// holding only the version encodes to the scaffold itself. Only
    /// known keys are written: anything unknown never survives decoding,
    /// so there is nothing else to keep.
    static func encode(_ config: ValidConfiguration) -> Data {
        var entries: [String] = []
        if let appearanceMode = config.appearanceMode {
            entries.append(encodedString(key: "appearanceMode", value: appearanceMode.rawValue))
        }
        if let fullscreenMode = config.fullscreenMode {
            entries.append(encodedString(key: "fullscreenMode", value: fullscreenMode.rawValue))
        }
        if let hiddenAppMode = config.hiddenAppMode {
            entries.append(encodedString(key: "hiddenAppMode", value: hiddenAppMode.rawValue))
        }
        if let launchAtLogin = config.launchAtLogin {
            entries.append(encodedBool(key: "launchAtLogin", value: launchAtLogin))
        }
        if let logLevel = config.logLevel {
            entries.append(encodedString(key: "logLevel", value: logLevel.rawValue))
        }
        if let minimizedMode = config.minimizedMode {
            entries.append(encodedString(key: "minimizedMode", value: minimizedMode.rawValue))
        }
        if let otherSpaceMode = config.otherSpaceMode {
            entries.append(encodedString(key: "otherSpaceMode", value: otherSpaceMode.rawValue))
        }
        if let romajiScope = config.romajiScope {
            entries.append(encodedString(key: "romajiScope", value: romajiScope.rawValue))
        }
        if let sampleCount = config.sampleCount {
            entries.append(encodedInt(key: "sampleCount", value: sampleCount))
        }
        if let stopMonitorEverySeconds = config.stopMonitorEverySeconds {
            entries.append(encodedInt(key: "stopMonitorEvery", value: stopMonitorEverySeconds))
        }
        entries.append(contentsOf: updateCheckEntries(config))
        entries.append(encodedInt(key: "version", value: config.version))
        return Data(("{\n" + entries.joined(separator: ",\n") + "\n}\n").utf8)
    }

    /// Writes encoded settings to the file, creating its directory.
    ///
    /// The write is atomic, so a failure leaves the previous file in
    /// place rather than a half-written one. Used only for saves coming
    /// from the settings UI; the launch path still never touches
    /// existing files.
    static func save(_ config: ValidConfiguration, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encode(config).write(to: url, options: .atomic)
    }

    /// The two update-check lines, in canonical order, skipping absent values.
    private static func updateCheckEntries(_ config: ValidConfiguration) -> [String] {
        var entries: [String] = []
        if let updateChannel = config.updateChannel {
            entries.append(encodedString(key: "updateChannel", value: updateChannel))
        }
        if let updateCheckEnabled = config.updateCheckEnabled {
            entries.append(encodedBool(key: "updateCheckEnabled", value: updateCheckEnabled))
        }
        return entries
    }

    /// One `"key": "value"` line, indented two spaces.
    private static func encodedString(key: String, value: String) -> String {
        "  \"\(key)\": \"\(value)\""
    }

    /// One `"key": 1` line, indented two spaces.
    private static func encodedInt(key: String, value: Int) -> String {
        "  \"\(key)\": \(value)"
    }

    /// One `"key": true` line, indented two spaces.
    private static func encodedBool(key: String, value: Bool) -> String {
        "  \"\(key)\": \(value)"
    }
}
