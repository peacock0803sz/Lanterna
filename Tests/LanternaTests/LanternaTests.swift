@testable import Lanterna
import Testing

struct LanternaTests {
    /// Smoke test: the executable module builds with testing enabled and links into the test bundle.
    @Test func entryPointIsReachable() {
        #expect(String(describing: Lanterna.self) == "Lanterna")
    }
}
