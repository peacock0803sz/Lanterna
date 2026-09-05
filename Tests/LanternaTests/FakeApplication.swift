import ApplicationServices
import Foundation
@testable import Lanterna

/// One application and its windows.
///
/// `@unchecked Sendable` because the reader's seams are `@Sendable`
/// closures, while these tests drive it synchronously on a single thread,
/// so there is nothing to protect. For these tests only: read through
/// `WindowEnumerator`, which reads on several threads at once, it would race.
final class FakeApplication: @unchecked Sendable {
    let windows: [AXUIElement]

    private(set) var preparedElements: [Int?] = []
    /// The timeout each of those elements was given.
    private(set) var preparedTimeouts: [Float] = []
    /// Every attribute read, in order, with the window it was read from;
    /// `nil` is the application itself.
    private(set) var reads: [(index: Int?, name: String)] = []
    private(set) var windowIDReads: [Int] = []
    /// Elements messaged before their timeout was set; such a message would
    /// have waited the multi-second default.
    private(set) var messagedBeforePrepared: [Int?] = []

    var attributesRead: [String] {
        reads.map { $0.name }
    }

    /// Time each message costs, so a budget can be spent without waiting.
    var costPerMessage: Duration = .zero
    /// Answers `nil` to fall through to `costPerMessage`. The index is the
    /// window's position, or `nil` for the application itself.
    var costOverride: @Sendable (Int?, String) -> Duration? = { _, _ in nil }
    /// Answers `nil` to fall through to `costPerMessage`.
    var windowIDCostOverride: @Sendable (Int) -> Duration? = { _ in nil }
    /// The answer itself rather than an override: setting a timeout always
    /// answers, `.success` unless a test says otherwise. The index is the
    /// window's position, or `nil` for the application itself.
    var timeoutResult: @Sendable (Int?) -> AXError = { _ in .success }
    /// Answers `nil` to fall through to `value(at:for:)`. The index is the
    /// window's position, or `nil` for the application itself.
    var attributeResult: @Sendable (Int?, String) -> (AXError, CFTypeRef?)? = { _, _ in nil }
    /// Answers `nil` to fall through to a successful fetch of `100 + index`.
    var windowIDResult: @Sendable (Int) -> (AXError, CGWindowID)? = { _ in nil }

    private var clock = ContinuousClock.now

    /// Distinct elements, so a closure can tell which window it was asked
    /// about. Creating one sends nothing and needs no permission.
    init(windowCount: Int) {
        windows = (0 ..< windowCount).map { AXUIElementCreateApplication(pid_t(9001 + $0)) }
    }

    func reader() -> AXApplicationWindowReader {
        AXApplicationWindowReader(
            setMessagingTimeout: { [self] element, timeout in
                // Client-side, so it costs no time and is charged nothing.
                let index = windowIndex(of: element)
                preparedElements.append(index)
                preparedTimeouts.append(timeout)
                return timeoutResult(index)
            },
            copyAttribute: { [self] element, name in
                let index = windowIndex(of: element)
                noteMessage(to: index)
                clock = clock.advanced(by: costOverride(index, name) ?? costPerMessage)
                reads.append((index, name))
                return attributeResult(index, name) ?? (.success, value(at: index, for: name))
            },
            copyWindowID: { [self] element in
                guard let index = windowIndex(of: element) else {
                    return (.illegalArgument, 0)
                }
                noteMessage(to: index)
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

    private func noteMessage(to index: Int?) {
        if !preparedElements.contains(index) {
            messagedBeforePrepared.append(index)
        }
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
        case kAXMinimizedAttribute: return kCFBooleanFalse
        default: return nil
        }
    }
}
