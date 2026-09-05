import ApplicationServices
import Foundation
@testable import Lanterna
import Testing

/// What the reader sends, and what it does with each answer.
///
/// Which error an application returns is the whole behaviour under test, and no
/// real application can be asked to return one, so a stand-in answers instead
/// and records every message it received.
struct AXApplicationWindowReaderMessagingTests {
    private typealias Reader = AXApplicationWindowReader

    /// One application and its windows.
    ///
    /// `@unchecked Sendable` because the reader's seams are `@Sendable`
    /// closures, while these tests drive it synchronously on a single thread,
    /// so there is nothing to protect.
    private final class FakeApplication: @unchecked Sendable {
        let windows: [AXUIElement]

        private(set) var preparedElements: [Int?] = []
        /// Every attribute read, in order, with the window it was read from;
        /// `nil` is the application itself.
        private(set) var reads: [(index: Int?, name: String)] = []
        private(set) var windowIDReads: [Int] = []

        var attributesRead: [String] {
            reads.map { $0.name }
        }

        /// Time each message costs, so a budget can be spent without waiting.
        var costPerMessage: Duration = .zero
        /// Answers `nil` to fall through to the default behaviour. The index is
        /// the window's position, or `nil` for the application itself.
        var costOverride: @Sendable (Int?, String) -> Duration? = { _, _ in nil }
        var windowIDCostOverride: @Sendable (Int) -> Duration? = { _ in nil }
        var timeoutResult: @Sendable (Int?) -> AXError = { _ in .success }
        var attributeResult: @Sendable (Int?, String) -> (AXError, CFTypeRef?)? = { _, _ in nil }
        var windowIDResult: @Sendable (Int) -> (AXError, CGWindowID)? = { _ in nil }

        private var clock = ContinuousClock.now

        /// Distinct elements, so a closure can tell which window it was asked
        /// about. Creating one sends nothing and needs no permission.
        init(windowCount: Int) {
            windows = (0 ..< windowCount).map { AXUIElementCreateApplication(pid_t(9001 + $0)) }
        }

        func reader() -> AXApplicationWindowReader {
            AXApplicationWindowReader(
                setMessagingTimeout: { [self] element, _ in
                    // Client-side, so it costs no time and is charged nothing.
                    let index = windowIndex(of: element)
                    preparedElements.append(index)
                    return timeoutResult(index)
                },
                copyAttribute: { [self] element, name in
                    let index = windowIndex(of: element)
                    clock = clock.advanced(by: costOverride(index, name) ?? costPerMessage)
                    reads.append((index, name))
                    return attributeResult(index, name) ?? (.success, value(at: index, for: name))
                },
                copyWindowID: { [self] element in
                    guard let index = windowIndex(of: element) else {
                        return (.illegalArgument, 0)
                    }
                    clock = clock.advanced(by: windowIDCostOverride(index) ?? costPerMessage)
                    windowIDReads.append(index)
                    return windowIDResult(index) ?? (.success, CGWindowID(100 + index))
                },
                now: { [self] in clock }
            )
        }

        func read() -> Result<ApplicationRead, ReadFailure> {
            reader().read(processIdentifier: 42)
        }

        /// The attributes read from one window, in order.
        func attributesRead(of index: Int) -> [String] {
            reads.filter { $0.index == index }.map { $0.name }
        }

        private func windowIndex(of element: AXUIElement) -> Int? {
            windows.firstIndex { CFEqual($0, element) }
        }

        /// An ordinary standard window, unless a test says otherwise.
        private func value(at index: Int?, for name: String) -> CFTypeRef? {
            guard let index else {
                return name == kAXWindowsAttribute ? windows as CFArray : nil
            }
            switch name {
            case kAXRoleAttribute: return kAXWindowRole as CFString
            case kAXSubroleAttribute: return kAXStandardWindowSubrole as CFString
            case kAXTitleAttribute: return "Window \(index)" as CFString
            case kAXMinimizedAttribute: return NSNumber(value: false)
            default: return nil
            }
        }
    }

    @Test func anOrdinaryApplicationYieldsOneRecordPerWindow() {
        let application = FakeApplication(windowCount: 2)
        let read = try? application.read().get()
        #expect(read?.records.map(\.windowID) == [100, 101])
        #expect(read?.droppedWithoutID == 0)
    }

    /// Only an absent value is an answer; anything else means the application
    /// could not be read, and its records go with it.
    @Test(arguments: [
        (AXError.noValue, nil),
        (.attributeUnsupported, nil),
        (.cannotComplete, ReadFailure.unavailable(.cannotComplete)),
        (.apiDisabled, .permissionMissing),
        (.invalidUIElement, .unavailable(.invalidUIElement)),
        (.illegalArgument, .unavailable(.illegalArgument)),
    ])
    func anAttributeErrorEitherMeansAbsentOrDiscardsTheApplication(
        error: AXError,
        failure: ReadFailure?
    ) {
        let application = FakeApplication(windowCount: 2)
        application.attributeResult = { index, name in
            index == 1 && name == kAXTitleAttribute ? (error, nil) : nil
        }

        switch application.read() {
        case let .success(read):
            #expect(failure == nil)
            // An untitled window is still a window.
            #expect(read.records.count == 2)
            #expect(read.records.last?.title == "")
        case let .failure(reason):
            #expect(reason == failure)
        }
    }

    /// A dead or unreachable application is answered with the same code as a
    /// timeout, only at once; how long the answer took is the only way to tell
    /// which of the two it was.
    @Test(arguments: [
        (Duration.zero, ReadFailure.unavailable(.cannotComplete)),
        (Reader.unreachableAnswerCeiling - .milliseconds(1), .unavailable(.cannotComplete)),
        (Reader.unreachableAnswerCeiling, .timedOut),
        (.seconds(Double(Reader.messagingTimeout)), .timedOut),
    ])
    func aCannotCompleteAnswerIsATimeoutOnlyIfItTookLongEnough(cost: Duration, failure: ReadFailure) {
        let application = FakeApplication(windowCount: 2)
        application.attributeResult = { index, name in
            index == 1 && name == kAXTitleAttribute ? (.cannotComplete, nil) : nil
        }
        application.costOverride = { index, name in
            index == 1 && name == kAXTitleAttribute ? cost : nil
        }
        #expect(application.read() == .failure(failure))
    }

    /// A partly read application is worse than a missing one, so nothing that
    /// was already gathered survives the failure.
    @Test func aFailureDiscardsTheRecordsAlreadyGathered() {
        let application = FakeApplication(windowCount: 3)
        application.attributeResult = { index, name in
            index == 2 && name == kAXRoleAttribute ? (.cannotComplete, nil) : nil
        }
        application.costOverride = { index, name in
            index == 2 && name == kAXRoleAttribute ? .seconds(1) : nil
        }
        #expect(application.read() == .failure(.timedOut))
    }

    @Test func nothingIsSentOnceTheBudgetIsSpent() {
        let application = FakeApplication(windowCount: 10)
        // Four messages fit in a one-second budget at this cost.
        application.costPerMessage = .milliseconds(400)

        #expect(application.read() == .failure(.timedOut))
        #expect(application.attributesRead == [
            kAXWindowsAttribute, kAXRoleAttribute, kAXSubroleAttribute,
        ])
        #expect(application.windowIDReads.isEmpty)
    }

    /// Without its timeout an element would be messaged with the multi-second
    /// default, so it is not messaged at all.
    @Test func anElementWhoseTimeoutCannotBeSetIsNeverMessaged() {
        let application = FakeApplication(windowCount: 2)
        application.timeoutResult = { $0 == 0 ? .cannotComplete : .success }

        #expect(application.read() == .failure(.unavailable(.cannotComplete)))
        #expect(application.attributesRead == [kAXWindowsAttribute])
        #expect(application.windowIDReads.isEmpty)
    }

    /// An element the rule table rules out — the Finder desktop, a font panel —
    /// is asked nothing more once its role and subrole are in. Every message
    /// is a round trip, and a failing one would discard the whole application
    /// over an element that was never going to be a row.
    @Test func anExcludedElementIsNotMessagedFurther() {
        let application = FakeApplication(windowCount: 2)
        application.attributeResult = { index, name in
            guard index == 0 else { return nil }
            switch name {
            case kAXRoleAttribute: return (.success, kAXScrollAreaRole as CFString)
            // Never sent, so it never gets the chance to fail the read.
            case kAXTitleAttribute: return (.invalidUIElement, nil)
            default: return nil
            }
        }

        let read = try? application.read().get()
        #expect(read?.records.map(\.windowID) == [101])
        #expect(read?.droppedWithoutID == 0)
        #expect(application.attributesRead(of: 0) == [kAXRoleAttribute, kAXSubroleAttribute])
        #expect(application.attributesRead(of: 1) == [
            kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute,
        ])
        #expect(application.windowIDReads == [1])
    }

    /// The window id is the one answer whose absence is ordinary, whether it
    /// comes as an error or as a zero id, so it costs its own row and nothing
    /// else.
    @Test(arguments: [AXError.illegalArgument, .invalidUIElement, .success])
    func aMissingWindowIDCostsOnlyItsOwnRow(error: AXError) {
        let application = FakeApplication(windowCount: 3)
        application.windowIDResult = { $0 == 1 ? (error, 0) : nil }

        let read = try? application.read().get()
        #expect(read?.records.map(\.windowID) == [100, 102])
        #expect(read?.droppedWithoutID == 1)
    }

    /// The id fetch is a round trip like any attribute read. Read as "no id",
    /// a hang on the last window would have turned that window into a dropped
    /// element and the others into a partial list of a hung application, the
    /// outcome discarding the whole application exists to avoid.
    @Test(arguments: [
        (Duration.zero, ReadFailure.unavailable(.cannotComplete)),
        (.seconds(1), .timedOut),
    ])
    func aCannotCompleteOnTheLastWindowIDFetchEndsTheRead(cost: Duration, failure: ReadFailure) {
        let application = FakeApplication(windowCount: 3)
        application.windowIDResult = { $0 == 2 ? (.cannotComplete, 0) : nil }
        application.windowIDCostOverride = { $0 == 2 ? cost : nil }

        #expect(application.read() == .failure(failure))
    }

    /// An application with nothing open answers an empty list, which is a
    /// normal read, not a skipped application.
    @Test func anApplicationWithoutWindowsReadsSuccessfully() {
        let application = FakeApplication(windowCount: 0)
        let read = try? application.read().get()
        #expect(read?.records.isEmpty == true)
    }

    /// "No value" is accepted as nothing open too. The windows behind the fake
    /// prove that the answer, not the default, produced the empty list.
    @Test func aWindowListWithNoValueReadsAsEmpty() {
        let application = FakeApplication(windowCount: 2)
        application.attributeResult = { _, name in
            name == kAXWindowsAttribute ? (.noValue, nil) : nil
        }

        let read = try? application.read().get()
        #expect(read?.records.isEmpty == true)
        #expect(application.attributesRead == [kAXWindowsAttribute])
    }

    /// Every live application answers the window list with an array, an empty
    /// one included, so anything else is an application that cannot be read,
    /// not one that is idle. Folding it into "no windows" would count the
    /// application without a row and without a reason.
    @Test(arguments: [
        (AXError.attributeUnsupported, nil, ReadFailure.unavailable(.attributeUnsupported)),
        (.success, "oops", .malformedAnswer),
    ])
    func anAbnormalWindowListAnswerDiscardsTheApplication(
        error: AXError,
        value: String?,
        failure: ReadFailure
    ) {
        let application = FakeApplication(windowCount: 2)
        application.attributeResult = { _, name in
            name == kAXWindowsAttribute ? (error, value as CFString?) : nil
        }

        #expect(application.read() == .failure(failure))
        #expect(application.attributesRead == [kAXWindowsAttribute])
    }
}
