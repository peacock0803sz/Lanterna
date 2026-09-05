import AppKit
@testable import Lanterna
import Testing

/// The assembly rules — grouping, ordering, fallbacks, isolation of a failing
/// application — all live in the enumerator, and a fake reader exercises them
/// without a live accessibility connection.
@MainActor
struct WindowEnumeratorTests {
    /// Answers from a table keyed by process identifier, so a test states what
    /// each application replies and nothing else.
    private struct FakeReader: ApplicationWindowReading {
        let reads: [pid_t: Result<ApplicationRead, ReadFailure>]

        init(_ reads: [pid_t: Result<ApplicationRead, ReadFailure>]) {
            self.reads = reads
        }

        func read(processIdentifier: pid_t) -> Result<ApplicationRead, ReadFailure> {
            reads[processIdentifier] ?? .success(ApplicationRead(records: [], droppedWithoutID: 0))
        }
    }

    private func application(
        _ processIdentifier: pid_t,
        name: String = "Finder"
    ) -> RunningApplicationInfo {
        RunningApplicationInfo(
            processIdentifier: processIdentifier,
            name: name,
            bundleIdentifier: nil,
            icon: NSImage()
        )
    }

    private func record(
        _ windowID: CGWindowID,
        title: String = "Downloads",
        kind: WindowKind = .standard,
        isMinimized: Bool = false
    ) -> WindowRecord {
        WindowRecord(windowID: windowID, title: title, kind: kind, isMinimized: isMinimized)
    }

    private func read(_ records: [WindowRecord], droppedWithoutID: Int = 0) -> Result<ApplicationRead, ReadFailure> {
        .success(ApplicationRead(records: records, droppedWithoutID: droppedWithoutID))
    }

    private func snapshot(
        applications: [RunningApplicationInfo],
        reads: [pid_t: Result<ApplicationRead, ReadFailure>]
    ) -> WindowListSnapshot {
        WindowEnumerator(reader: FakeReader(reads)).enumerate(
            applications: applications,
            startedAt: .now
        )
    }

    // MARK: - Ordering

    /// The input is unsorted on purpose: the ids prove that each application
    /// kept its own read through the sort, not only its place.
    @Test func applicationsAreGroupedInProcessIdentifierOrder() {
        let result = snapshot(
            applications: [application(300, name: "Mail"), application(100, name: "Finder")],
            reads: [300: read([record(9)]), 100: read([record(7)])]
        )
        #expect(result.items.map(\.appName) == ["Finder", "Mail"])
        #expect(result.items.map(\.ownerProcessIdentifier) == [100, 300])
        #expect(result.items.map(\.id.windowID) == [7, 9])
    }

    /// The accessibility list is ordered front to back, so it changes whenever
    /// another window of the same application comes forward.
    @Test func windowsOfOneApplicationAreOrderedByWindowID() {
        let result = snapshot(
            applications: [application(100)],
            reads: [100: read([record(30), record(10), record(20)])]
        )
        #expect(result.items.map(\.id.windowID) == [10, 20, 30])
    }

    @Test func orderDoesNotFollowTheOrderOfTheInput() {
        let forwards = snapshot(
            applications: [application(100), application(300, name: "Mail")],
            reads: [100: read([record(10), record(20)]), 300: read([record(9)])]
        )
        let backwards = snapshot(
            applications: [application(300, name: "Mail"), application(100)],
            reads: [100: read([record(20), record(10)]), 300: read([record(9)])]
        )
        #expect(forwards.items.map(\.id) == backwards.items.map(\.id))
    }

    /// Two copies of one application are two processes, and they must not
    /// interleave.
    @Test func applicationsSharingANameStayInTwoAdjacentGroups() {
        let result = snapshot(
            applications: [
                application(100, name: "Safari"),
                application(200, name: "Safari"),
                application(150, name: "Mail"),
            ],
            reads: [100: read([record(1)]), 200: read([record(2)]), 150: read([record(3)])]
        )
        #expect(result.items.map(\.ownerProcessIdentifier) == [100, 150, 200])
    }

    // MARK: - Row content

    @Test func windowsSharingATitleBecomeTwoRows() {
        let result = snapshot(
            applications: [application(100)],
            reads: [100: read([record(10, title: "Downloads"), record(11, title: "Downloads")])]
        )
        #expect(result.items.count == 2)
        #expect(Set(result.items.map(\.id)).count == 2)
    }

    @Test(arguments: ["", " ", "\n"])
    func aBlankTitleIsShownAsTheApplicationName(title: String) {
        let result = snapshot(
            applications: [application(100, name: "Ghostty")],
            reads: [100: read([record(10, title: title)])]
        )
        #expect(result.items.first?.displayTitle == "Ghostty")
    }

    @Test func recordDetailReachesTheRow() {
        let result = snapshot(
            applications: [application(100)],
            reads: [100: read([record(10, kind: .dialog, isMinimized: true)])]
        )
        #expect(result.items.first?.kind == .dialog)
        #expect(result.items.first?.isMinimized == true)
    }

    @Test func idsAreUniqueAcrossTheWholeList() {
        let result = snapshot(
            applications: [application(100), application(200, name: "Mail")],
            reads: [100: read([record(10), record(11)]), 200: read([record(12)])]
        )
        #expect(Set(result.items.map(\.id)).count == result.items.count)
    }

    // MARK: - Counting

    @Test func droppedElementsAreSummedAcrossApplications() {
        let result = snapshot(
            applications: [application(100), application(200, name: "Mail")],
            reads: [
                100: read([record(10)], droppedWithoutID: 2),
                200: read([], droppedWithoutID: 3),
            ]
        )
        #expect(result.droppedWithoutID == 5)
    }

    @Test func everyApplicationIsCountedIncludingSkippedOnes() {
        let result = snapshot(
            applications: [application(100), application(200, name: "Mail")],
            reads: [100: read([record(10)]), 200: .failure(.timedOut)]
        )
        #expect(result.applicationCount == 2)
    }

    /// An application with no open window is a normal answer, not a failure.
    @Test func anApplicationWithoutWindowsIsNeitherListedNorSkipped() {
        let result = snapshot(
            applications: [application(100)],
            reads: [100: read([])]
        )
        #expect(result.items.isEmpty)
        #expect(result.skipped.isEmpty)
    }

    /// Nothing in the Dock at all leaves the concurrent read with no work to
    /// fan out, and must still come back as an ordinary, empty snapshot.
    @Test func noApplicationsMakeAnEmptySnapshot() {
        let result = snapshot(applications: [], reads: [:])
        #expect(result.items.isEmpty)
        #expect(result.applicationCount == 0)
        #expect(result.skipped.isEmpty)
        #expect(result.droppedWithoutID == 0)
    }

    // MARK: - Isolating a failing application

    /// One application that cannot be read must not cost the others their rows.
    @Test(arguments: [ReadFailure.timedOut, .permissionMissing, .unavailable(.invalidUIElement)])
    func anApplicationThatFailsIsNamedAndLeavesTheRestIntact(reason: ReadFailure) {
        let result = snapshot(
            applications: [
                application(100, name: "Finder"),
                application(200, name: "TextEdit"),
                application(300, name: "Mail"),
            ],
            reads: [
                100: read([record(10), record(11)]),
                200: .failure(reason),
                300: read([record(12)]),
            ]
        )
        #expect(result.items.map(\.id.windowID) == [10, 11, 12])
        #expect(result.skipped.map(\.name) == ["TextEdit"])
        #expect(result.skipped.first?.reason == reason)
    }

    @Test func skippedApplicationsAreListedInApplicationOrder() {
        let result = snapshot(
            applications: [
                application(300, name: "Mail"),
                application(100, name: "Finder"),
            ],
            reads: [300: .failure(.permissionMissing), 100: .failure(.timedOut)]
        )
        #expect(result.skipped.map(\.name) == ["Finder", "Mail"])
        #expect(result.skipped.map(\.reason) == [.timedOut, .permissionMissing])
    }

    // MARK: - Candidate applications

    @Test(arguments: [NSApplication.ActivationPolicy.accessory, .prohibited])
    func onlyDockedApplicationsAreCandidates(policy: NSApplication.ActivationPolicy) {
        #expect(!RunningApplicationInfo.isCandidate(
            activationPolicy: policy,
            processIdentifier: 100,
            currentProcess: 1
        ))
        #expect(RunningApplicationInfo.isCandidate(
            activationPolicy: .regular,
            processIdentifier: 100,
            currentProcess: 1
        ))
    }

    @Test func theSwitcherDoesNotListItself() {
        #expect(!RunningApplicationInfo.isCandidate(
            activationPolicy: .regular,
            processIdentifier: 100,
            currentProcess: 100
        ))
    }

    // MARK: - Application name and icon

    @Test func theNameIsTheOneShownInTheDock() {
        #expect(RunningApplicationInfo.displayName(
            localizedName: "Safari",
            bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            executableURL: nil,
            processIdentifier: 42
        ) == "Safari")
    }

    @Test(arguments: ["", " ", "\n"])
    func aBlankLocalizedNameFallsBackToTheBundleName(localizedName: String) {
        #expect(RunningApplicationInfo.displayName(
            localizedName: localizedName,
            bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            executableURL: URL(fileURLWithPath: "/usr/bin/whatever"),
            processIdentifier: 42
        ) == "Safari")
    }

    @Test func anApplicationWithoutABundleFallsBackToItsExecutable() {
        #expect(RunningApplicationInfo.displayName(
            localizedName: nil,
            bundleURL: nil,
            executableURL: URL(fileURLWithPath: "/usr/local/bin/probe"),
            processIdentifier: 42
        ) == "probe")
    }

    @Test func theLastResortNamesTheProcess() {
        #expect(RunningApplicationInfo.displayName(
            localizedName: nil,
            bundleURL: nil,
            executableURL: nil,
            processIdentifier: 42
        ) == "pid 42")
    }

    @Test func theNameIsNeverEmpty() {
        #expect(!RunningApplicationInfo.displayName(
            localizedName: "",
            bundleURL: nil,
            executableURL: nil,
            processIdentifier: 42
        ).isEmpty)
    }

    @Test func anApplicationWithoutAnIconSharesThePlaceholder() {
        #expect(RunningApplicationInfo.resolvedIcon(nil) === AppIconResolver.placeholder)
        let icon = NSImage()
        #expect(RunningApplicationInfo.resolvedIcon(icon) === icon)
    }
}
