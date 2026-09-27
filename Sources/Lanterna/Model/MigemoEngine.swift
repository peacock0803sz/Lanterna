import CMigemo
import Foundation

/// A thin wrapper over the vendored matching engine.
///
/// The wrapper owns the engine's lifetime and translates between Swift
/// strings and the engine's byte strings. Pattern details stay inside
/// the engine; Swift only opens, asks, and closes. Queries the engine
/// cannot parse fall back to a literal match (see `escapedLiteral`).
///
/// Not `Sendable`: the C handle is not thread-safe. Confine each
/// instance to its owning execution context.
struct MigemoEngine {
    /// An open engine handle, or nil while closed.
    private var handle: OpaquePointer?

    /// Whether the engine is open and ready to answer queries.
    var isOpen: Bool {
        handle != nil
    }

    /// Opens the engine, loading the dictionary at the given path.
    ///
    /// A nil path opens the engine without a dictionary, in which case
    /// only kana readings match. Returns false when opening fails.
    @discardableResult
    mutating func open(dictionaryPath: String?) -> Bool {
        close()
        let handle: OpaquePointer?
        if let dictionaryPath {
            handle = dictionaryPath.withCString { path in
                migemo_open(path)
            }
        } else {
            handle = migemo_open(nil)
        }
        self.handle = handle
        return handle != nil
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
    mutating func close() {
        if let handle {
            migemo_close(handle)
            self.handle = nil
        }
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
