import Dispatch
import Synchronization

/// Turns the running applications into the list the panel draws.
///
/// Main-actor bound because the names and icons it joins onto the rows come
/// from `RunningApplicationInfo`, which is kept on the main thread. The
/// reading itself is handed to worker threads, which see nothing but process
/// identifiers.
@MainActor
struct WindowEnumerator {
    private let reader: any ApplicationWindowReading

    init(reader: any ApplicationWindowReading = AXApplicationWindowReader()) {
        self.reader = reader
    }

    /// Reads every application at once and assembles the rows in a fixed order.
    ///
    /// Applications are read in parallel because the first message to a process
    /// costs far more than the rest; each application still pays its own, but
    /// in parallel those costs overlap instead of adding up, which is what
    /// keeps the pass inside its budget. Order therefore cannot come from
    /// completion: it comes from the process identifier and the window id,
    /// neither of which changes while the process or window exists, so a list
    /// of the same windows always reads the same way.
    func enumerate(
        applications: [RunningApplicationInfo],
        startedAt: ContinuousClock.Instant
    ) -> WindowListSnapshot {
        let ordered = applications.sorted { $0.processIdentifier < $1.processIdentifier }
        return assemble(
            ordered,
            Self.read(ordered.map(\.processIdentifier), using: reader),
            startedAt: startedAt
        )
    }

    /// The same pass, with the reading kept off the main thread.
    ///
    /// `read(_:using:)` blocks the thread it runs on until every application
    /// has answered, which is about a second when one of them has stopped
    /// answering. On the main thread that second is a second the panel cannot
    /// be drawn in, so the call is sent elsewhere and waited for.
    ///
    /// A global queue rather than `Task.detached`, because blocking is exactly
    /// what this work does. Swift concurrency's cooperative pool has about one
    /// thread per core and expects them to suspend rather than block; a
    /// detached task parked inside `concurrentPerform` holds those threads
    /// against everything else that wants them. A Dispatch queue is the pool
    /// that is allowed to be blocked. A `TaskGroup` was turned down for the
    /// reading itself over the same distinction.
    ///
    /// Only the identifiers cross: the names and icons stay on this side and
    /// are joined on afterwards, which is what lets `RunningApplicationInfo`
    /// remain main-actor bound.
    func enumerateOffMainThread(
        applications: [RunningApplicationInfo],
        startedAt: ContinuousClock.Instant
    ) async -> WindowListSnapshot {
        let ordered = applications.sorted { $0.processIdentifier < $1.processIdentifier }
        let identifiers = ordered.map(\.processIdentifier)
        let reader = reader
        let results = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.read(identifiers, using: reader))
            }
        }
        return assemble(ordered, results, startedAt: startedAt)
    }

    /// Every running application that shows in the Dock, and its windows, with
    /// the reading kept off the main thread. The refresh loop's pass.
    ///
    /// Collecting the applications stays here, on the main actor, because
    /// `NSWorkspace` and the names and icons it yields belong to the main
    /// thread. It costs a few milliseconds; the reading is the part worth
    /// moving.
    func enumerateRegularApplicationsOffMainThread() async -> WindowListSnapshot {
        // Started before the applications are collected, because resolving
        // names and icons is part of what a pass costs.
        let startedAt = ContinuousClock.now
        return await enumerateOffMainThread(
            applications: RunningApplicationInfo.regularApplications(),
            startedAt: startedAt
        )
    }

    /// Joins each application to its answer and lays the rows out.
    ///
    /// Shared by both paths so that moving the reading cannot quietly change
    /// the list. Main-actor bound because `RunningApplicationInfo` is: this is
    /// where the names and icons are attached.
    private func assemble(
        _ ordered: [RunningApplicationInfo],
        _ results: [Result<ApplicationRead, ReadFailure>],
        startedAt: ContinuousClock.Instant
    ) -> WindowListSnapshot {
        var items: [WindowItem] = []
        var skipped: [WindowListSnapshot.SkippedApplication] = []
        var droppedWithoutID = 0
        for (application, result) in zip(ordered, results) {
            switch result {
            case let .failure(reason):
                skipped.append(
                    WindowListSnapshot.SkippedApplication(name: application.name, reason: reason)
                )
            case let .success(read):
                droppedWithoutID += read.droppedWithoutID
                items.append(
                    contentsOf: read.records
                        .sorted { $0.windowID < $1.windowID }
                        .map { item(for: $0, of: application) }
                )
            }
        }

        return WindowListSnapshot(
            items: items,
            applicationCount: ordered.count,
            gatheringDuration: ContinuousClock.now - startedAt,
            skipped: skipped,
            droppedWithoutID: droppedWithoutID
        )
    }

    private func item(
        for record: WindowRecord,
        of application: RunningApplicationInfo
    ) -> WindowItem {
        WindowItem(
            id: WindowItem.Identifier(windowID: record.windowID),
            ownerProcessIdentifier: application.processIdentifier,
            appName: application.name,
            bundleIdentifier: application.bundleIdentifier,
            windowTitle: record.title,
            kind: record.kind,
            isMinimized: record.isMinimized,
            icon: application.icon
        )
    }

    /// Reads all applications concurrently, one result per input position.
    ///
    /// The closure `concurrentPerform` runs is `@Sendable`, so it could not
    /// touch main-actor state whatever this function's isolation; `nonisolated`
    /// records that the function needs nothing from the main actor. The calling
    /// thread takes part in the iterations and blocks until every application
    /// has answered. Results are written to a fixed slot rather than appended,
    /// so a slow application changes when a row arrives but never where it
    /// lands.
    ///
    /// `concurrentPerform` does not overcommit: its width is roughly the active
    /// core count. One wedged application therefore costs about one second in
    /// total, but more of them wedged at once than that width serialise into
    /// waves of about a second each.
    private nonisolated static func read(
        _ identifiers: [pid_t],
        using reader: any ApplicationWindowReading
    ) -> [Result<ApplicationRead, ReadFailure>] {
        guard !identifiers.isEmpty else {
            return []
        }
        let slots = Mutex<[Result<ApplicationRead, ReadFailure>?]>(
            Array(repeating: nil, count: identifiers.count)
        )
        DispatchQueue.concurrentPerform(iterations: identifiers.count) { index in
            let result = reader.read(processIdentifier: identifiers[index])
            slots.withLock { $0[index] = result }
        }
        // Every iteration fills its own slot. Dropping an unwritten one instead
        // would misalign the results against the applications they belong to.
        return slots.withLock { $0 }.enumerated().map { index, result in
            guard let result else {
                preconditionFailure("application \(index) left its slot unwritten")
            }
            return result
        }
    }
}
