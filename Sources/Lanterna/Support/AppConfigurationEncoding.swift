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
        entries.append(contentsOf: exclusionEntries(config))
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

    /// The exclusion list lines, in canonical order, skipping absence.
    private static func exclusionEntries(_ config: ValidConfiguration) -> [String] {
        guard let exclusions = config.exclusions else { return [] }
        return [encodedExclusions(key: "exclusions", value: exclusions)]
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

    /// The exclusion list lines. Entries keep their order; absent means
    /// no line, so a configuration without exclusions encodes unchanged.
    private static func encodedExclusions(key: String, value: [ExclusionEntry]) -> String {
        let rows = value.map { entry in
            "    { \"app\": \"\(escaped(entry.app))\", \"titlePattern\": \"\(escaped(entry.titlePattern))\" }"
        }
        return "  \"\(key)\": [\n" + rows.joined(separator: ",\n") + "\n  ]"
    }

    /// Escapes free text for the canonical form. Control characters,
    /// quotes and backslashes are the only ones JSON refuses raw.
    private static func escaped(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22:
                out += "\\\""
            case 0x5C:
                out += "\\\\"
            case 0x0A:
                out += "\\n"
            case 0x0D:
                out += "\\r"
            case 0x09:
                out += "\\t"
            case 0x00 ... 0x1F:
                out += String(format: "\\u%04x", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out
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
