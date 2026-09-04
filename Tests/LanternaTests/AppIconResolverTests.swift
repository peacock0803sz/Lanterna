import AppKit
@testable import Lanterna
import Testing

@MainActor
struct AppIconResolverTests {
    @Test func entryWithoutABundleIdentifierGetsThePlaceholder() {
        #expect(AppIconResolver.icon(forBundleIdentifier: nil) === AppIconResolver.placeholder)
    }

    @Test func uninstalledApplicationGetsThePlaceholder() {
        let icon = AppIconResolver.icon(forBundleIdentifier: "com.example.lanterna.uninstalled")
        #expect(icon === AppIconResolver.placeholder)
    }

    @Test func installedApplicationGetsItsOwnIcon() {
        // Finder is present on every macOS installation.
        let icon = AppIconResolver.icon(forBundleIdentifier: "com.apple.finder")
        #expect(icon !== AppIconResolver.placeholder)
    }

    @Test func repeatedLookupsShareOneImage() {
        #expect(
            AppIconResolver.icon(forBundleIdentifier: "com.apple.finder")
                === AppIconResolver.icon(forBundleIdentifier: "com.apple.finder")
        )
    }
}
