import Darwin
import Dispatch

/// Catches the signals that ask the process to stop, so it can undo what it
/// did to the system before it goes.
///
/// A raw `signal` handler cannot do that work: only async-signal-safe
/// functions may run inside one, which rules out almost everything. A dispatch
/// source instead delivers the signal as an ordinary block on the main queue,
/// long after the signal itself has been handled, so main-actor code is safe
/// to call from it.
@MainActor
enum TerminationSignals {
    /// The signals that mean "stop": Ctrl+C, a plain `kill` or `pkill`, and a
    /// closed terminal. SIGKILL is absent and cannot be added — nothing in the
    /// process runs after it.
    private static let caught: [Int32] = [SIGINT, SIGTERM, SIGHUP]

    /// A source stops delivering as soon as it is released, so they are kept
    /// for the life of the process.
    private static var sources: [any DispatchSourceSignal] = []

    /// Runs `cleanUp` and exits, once, for whichever of the signals arrives.
    ///
    /// Exiting here means `applicationWillTerminate` never runs on this path,
    /// so `cleanUp` has to be the whole of the shutdown rather than a part
    /// of it.
    static func install(cleanUp: @escaping @Sendable @MainActor () -> Void) {
        for number in caught {
            // Without this the default disposition kills the process outright,
            // before any dispatch source is woken. Ignoring the signal does
            // not hide it from the source.
            signal(number, SIG_IGN)

            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                // The handler was given the main queue, so this is the main
                // actor's executor; nothing weaker than a trap is wanted if
                // that ever stops being true.
                MainActor.assumeIsolated(cleanUp)
                exit(0)
            }
            source.resume()
            sources.append(source)
        }
    }
}
