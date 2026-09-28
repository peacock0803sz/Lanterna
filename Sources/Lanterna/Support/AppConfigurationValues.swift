import Foundation
import Logging

/// One optional key at a time, split out when the decoding file reached
/// the file-length limit. The shape of the file stays in `AppConfiguration`;
/// everything that reads a single key lives here.
extension AppConfiguration {
    /// Reads the on-off, channel and log-level keys together, so the assembly stays small.
    static func checkedSwitches(
        _ dict: [String: Any],
        into config: inout ValidConfiguration
    ) -> Result<Void, ConfigDecodeError> {
        switch checkedOptionalLogLevel(dict, key: "logLevel") {
        case let .success(found):
            config.logLevel = found
        case let .failure(error):
            return .failure(error)
        }
        switch checkedOptionalBool(dict, key: "launchAtLogin") {
        case let .success(found):
            config.launchAtLogin = found
        case let .failure(error):
            return .failure(error)
        }
        switch checkedOptionalBool(dict, key: "updateCheckEnabled") {
        case let .success(found):
            config.updateCheckEnabled = found
        case let .failure(error):
            return .failure(error)
        }
        switch checkedOptionalChannel(dict, key: "updateChannel") {
        case let .success(found):
            config.updateChannel = found
        case let .failure(error):
            return .failure(error)
        }
        return .success(())
    }

    /// Reads one optional integer key with its lower bound.
    static func checkedOptionalInt(
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

    /// Reads the count keys together, so `decode` stays small.
    static func checkedCountOptions(_ dict: [String: Any]) -> Result<
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

    /// Reads one optional boolean key. Only a real boolean counts:
    /// integers are refused the way booleans are refused for integers.
    static func checkedOptionalBool(
        _ dict: [String: Any],
        key: String
    ) -> Result<Bool?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let number = rawValue as? NSNumber,
              String(cString: number.objCType) == "c"
        else {
            return .failure(.invalidValue(key: key))
        }
        return .success(number.boolValue)
    }

    /// Reads the optional log-level key. Only the four words count:
    /// anything else invalidates the whole file, like any other bad value.
    static func checkedOptionalLogLevel(
        _ dict: [String: Any],
        key: String
    ) -> Result<Logger.Level?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let text = rawValue as? String, let level = Logger.Level.parse(word: text) else {
            return .failure(.invalidValue(key: key))
        }
        return .success(level)
    }

    /// Reads one optional display-mode key. Anything but a `DisplayMode`
    /// word invalidates the whole file, like any other bad value.
    static func checkedOptionalMode(
        _ dict: [String: Any],
        key: String
    ) -> Result<DisplayMode?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let text = rawValue as? String, let mode = DisplayMode(rawValue: text) else {
            return .failure(.invalidValue(key: key))
        }
        return .success(mode)
    }

    /// Reads the optional appearance-mode key. Anything but an
    /// `AppearanceMode` word invalidates the whole file, like any other
    /// bad value.
    static func checkedOptionalAppearance(
        _ dict: [String: Any],
        key: String
    ) -> Result<AppearanceMode?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let text = rawValue as? String, let mode = AppearanceMode(rawValue: text) else {
            return .failure(.invalidValue(key: key))
        }
        return .success(mode)
    }

    /// Reads the optional romaji-scope key. Anything but a
    /// `RomajiScope` word invalidates the whole file, like any other
    /// bad value.
    static func checkedOptionalRomajiScope(
        _ dict: [String: Any],
        key: String
    ) -> Result<RomajiScope?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let text = rawValue as? String, let scope = RomajiScope(rawValue: text) else {
            return .failure(.invalidValue(key: key))
        }
        return .success(scope)
    }

    /// Reads one optional channel key. Only the two known words count:
    /// anything else invalidates the whole file, like any other bad value.
    static func checkedOptionalChannel(
        _ dict: [String: Any],
        key: String
    ) -> Result<String?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let text = rawValue as? String,
              text == "stable" || text == "beta"
        else {
            return .failure(.invalidValue(key: key))
        }
        return .success(text)
    }

    /// Reads the optional exclusion list. The value must be an array;
    /// anything else invalidates the whole file. Elements that are not
    /// objects, or lack string app and titlePattern pairs, or carry
    /// extra keys, are skipped one by one while valid elements are kept.
    /// Value problems stay raw here: compiling reports what it skips, so
    /// decoding never decides what counts as unreadable.
    static func checkedOptionalExclusions(
        _ dict: [String: Any],
        key: String
    ) -> Result<[ExclusionEntry]?, ConfigDecodeError> {
        guard let rawValue = dict[key] else { return .success(nil) }
        guard let items = rawValue as? [Any] else {
            return .failure(.invalidValue(key: key))
        }
        var entries: [ExclusionEntry] = []
        for item in items {
            guard let element = item as? [String: Any],
                  Set(element.keys) == Set(["app", "titlePattern"]),
                  let app = element["app"] as? String,
                  let titlePattern = element["titlePattern"] as? String
            else {
                continue
            }
            entries.append(ExclusionEntry(app: app, titlePattern: titlePattern))
        }
        return .success(entries)
    }

    /// A JSON integer and nothing else.
    ///
    /// Booleans are refused by their Objective-C type: an `is Bool` check
    /// wrongly matches integer 1, so only the `c` type is turned away.
    static func jsonInt(_ value: Any) -> Int? {
        if let number = value as? NSNumber, String(cString: number.objCType) == "c" {
            return nil
        }
        return value as? Int
    }
}
