import AppKit
import Foundation
import SwiftUI

/// The on-screen version, straight from the generated file.
struct DisplayedVersion: Equatable {
    /// The full describe string, exactly as `Version.swift` holds it.
    let full: String
}

/// One log row as the view shows it.
struct DisplayedLogEntry: Identifiable, Equatable {
    var id: UInt64 {
        sequence
    }

    /// The store sequence, proving the order.
    let sequence: UInt64
    /// When the line was emitted, for reading only.
    let capturedAt: Date
    /// The line itself.
    let message: String
}

/// The version and log window.
///
/// Independent from the onboarding window: it opens from the menu-bar entry on
/// any launch, whether or not anything is missing. It reads the store without
/// changing it, and it owns no keyboard monitoring of any kind.
@MainActor
final class VersionLogWindow: NSWindow {
    /// Shows this launch so far: the version, the pinned summary, then the
    /// mirrored lines in order. A snapshot at opening time; reopening takes a
    /// fresh one.
    convenience init(
        version: DisplayedVersion,
        summary: String?,
        entries: [DisplayedLogEntry]
    ) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Lanterna Version and Logs"
        contentView = NSHostingView(rootView: VersionLogView(
            version: version,
            summary: summary,
            entries: entries
        ))
        center()
    }
}

/// The version and log contents.
///
/// Everything here is selectable, so a report can be copied out rather than
/// retyped. Nothing here edits.
struct VersionLogView: View {
    let version: DisplayedVersion
    let summary: String?
    let entries: [DisplayedLogEntry]

    /// Fixed shape so a report reads the same in every locale.
    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 40, height: 40)
                }
                VStack(alignment: .leading) {
                    Text("Lanterna \(version.full)")
                        .font(.headline)
                        .textSelection(.enabled)
                    if let summary {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text("#\(entry.sequence)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(Self.timeFormat.string(from: entry.capturedAt))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .font(.system(.body, design: .monospaced))
                        }
                        .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 560, height: 420)
    }
}
