import CMigemo
import Foundation

/// A thin wrapper over the vendored matching engine.
///
/// The wrapper owns the engine's lifetime and translates between Swift
/// strings and the engine's byte strings. Pattern details stay inside
/// the engine; Swift only opens, asks, and closes. Queries the engine
/// cannot parse fall back to a literal match (see `escapedLiteral`).
///
/// A reference type because the C handle must close exactly once.
/// Confine each instance to its owning execution context.
final class MigemoEngine {
    /// An open engine handle, or nil while closed.
    private var handle: OpaquePointer?

    /// Whether the engine is open and ready to answer queries.
    var isOpen: Bool {
        handle != nil
    }

    /// Opens the engine and loads the kana tables.
    ///
    /// When `dictionaryPath` names a readable dictionary, kanji readings
    /// match as well; with nil only kana readings match. The kana tables
    /// always come from `tableDirectory`. Returns false when opening or
    /// loading the tables fails.
    @discardableResult
    func open(dictionaryPath: String?, tableDirectory: String) -> Bool {
        close()
        let opened: OpaquePointer?
        if let dictionaryPath {
            opened = dictionaryPath.withCString { path in
                lanterna_migemo_open_utf8(path)
            }
        } else {
            opened = lanterna_migemo_open_utf8(nil)
        }
        guard let opened else { return false }
        handle = opened
        loadTables(from: tableDirectory)
        return true
    }

    /// Generates a matching pattern for the query, or nil when closed.
    ///
    /// The caller owns nothing: the pattern string is copied out before
    /// the engine's buffer is released.
    func pattern(for query: String) -> String? {
        guard let handle else { return nil }
        guard let raw = query.withCString({ queryCString in
            queryCString.withMemoryRebound(to: UInt8.self, capacity: 1) { rebound in
                migemo_query(handle, rebound)
            }
        }) else { return nil }
        defer { migemo_release(handle, raw) }
        let cString = UnsafeRawPointer(raw).assumingMemoryBound(to: CChar.self)
        return String(cString: cString)
    }

    /// Closes the engine, freeing its resources. Safe to call twice.
    func close() {
        if let handle {
            migemo_close(handle)
            self.handle = nil
        }
    }

    deinit {
        close()
    }

    /// Loads the kana conversion tables, ignoring single failures.
    ///
    /// The engine tolerates missing tables by matching less; loading is
    /// best-effort so a damaged table cannot take the filter down.
    private func loadTables(from directory: String) {
        guard let handle else { return }
        let tables: [(Int32, String)] = [
            (MIGEMO_DICTID_ROMA2HIRA, "roma2hira.dat"),
            (MIGEMO_DICTID_HIRA2KATA, "hira2kata.dat"),
            (MIGEMO_DICTID_HAN2ZEN, "han2zen.dat"),
            (MIGEMO_DICTID_ZEN2HAN, "zen2han.dat"),
        ]
        for (id, name) in tables {
            let path = (directory as NSString).appendingPathComponent(name)
            // migemo_load takes ownership of nothing; result ignored.
            _ = path.withCString { pointer in
                migemo_load(handle, id, pointer)
            }
        }
    }

    /// Locates the kana table directory.
    ///
    /// Prefers the resource bundle next to the running executable
    /// (installed and built products), falling back to the vendored
    /// sources beside this file (tests and source checkouts).
    static func tableDirectoryURL() -> URL? {
        let manager = FileManager.default
        if let executable = Bundle.main.executableURL {
            let candidate = executable.deletingLastPathComponent()
                .appendingPathComponent("Lanterna_CMigemo.bundle", isDirectory: true)
                .appendingPathComponent("Contents/Resources/tables", isDirectory: true)
            if manager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        let anchor = URL(fileURLWithPath: #filePath)
        let candidate = anchor.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CMigemo/tables", isDirectory: true)
        if manager.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    /// Escapes a query so it matches literally.
    ///
    /// Used when a query cannot be read as a pattern: every regular
    /// expression metacharacter is backslash-escaped, so the result
    /// matches only itself.
    static func escapedLiteral(_ query: String) -> String {
        let metacharacters = "\\^$.|?*+()[]{}"
        var escaped = ""
        escaped.reserveCapacity(query.count)
        for character in query {
            if metacharacters.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }
}
