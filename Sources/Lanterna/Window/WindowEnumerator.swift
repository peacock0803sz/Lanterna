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

    /// The launch path: every running application that shows in the Dock, and
    /// its windows.
    func enumerateRegularApplications() -> WindowListSnapshot {
        // Started before the applications are collected, because resolving
        // names and icons is part of what the panel waits for.
        let startedAt = ContinuousClock.now
        return enumerate(
            applications: RunningApplicationInfo.regularApplications(),
            startedAt: startedAt
        )
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
        let results = Self.read(ordered.map(\.processIdentifier), using: reader)

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
