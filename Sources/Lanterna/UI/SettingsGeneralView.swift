import SwiftUI

// MARK: - UpdateCheckDisplay

/// What the General tab shows about the last manual check.
///
/// Owned by the settings window; the General tab root only observes it.
/// The text starts unset and is replaced on every check, never carried
/// across launches.
@MainActor
final class UpdateCheckDisplay: ObservableObject {
  @Published var resultText: String?
  @Published var isChecking = false
}

// MARK: - SettingsGeneralView

/// The General tab in a grouped form.
///
/// About sits at the top without a header, followed by startup,
/// update, and permission sections. Permission rows show the state
/// captured at launch; a grant given while running appears after the
/// next launch.
struct SettingsGeneralView: View {

  // MARK: Internal

  @Binding var values: SettingsValues

  let version: DisplayedVersion
  let missing: [MissingPermission]
  let opener: SettingsOpener
  var launchSummary: String?
  var checkResultText: String?
  var isChecking = false
  var onCheckNow: () -> Void = { }
  var onOpenLogs: () -> Void = { }
  var savedLogs: () -> LogPersistence.ArchiveStatus = {
    LogPersistence.ArchiveStatus(totalBytes: 0, launchCount: 0, oldest: nil)
  }

  var onDeleteSavedLogs: () -> Void = { }

  var body: some View {
    Form {
      Section {
        HStack(spacing: 10) {
          if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon)
              .resizable()
              .frame(width: 40, height: 40)
          }
          VStack(alignment: .leading) {
            Text("Lanterna")
              .font(.headline)
            Text(version.full)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
            if let launchSummary {
              Text(launchSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }
          Spacer()
          Button("Open version history") {
            _ = opener(UpdateCheck.releasesPageURL)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }
      Section("Startup") {
        Toggle(isOn: $values.launchAtLogin) {
          SettingsFormLabel(
            title: "Launch at login",
            caption: "Start Lanterna automatically when you log in."
          )
        }
      }
      Section("Updates") {
        Toggle(isOn: $values.updateCheckEnabled) {
          SettingsFormLabel(
            title: "Check for updates",
            caption: "Ask whether a newer release is published."
          )
        }
        .disabled(isChecking)
        Picker(selection: $values.updateChannel) {
          Text("Stable").tag(UpdateChannel.stable)
          Text("Beta").tag(UpdateChannel.beta)
        } label: {
          SettingsFormLabel(
            title: "Channel",
            caption: "Stable covers full releases only. Beta also covers prereleases."
          )
        }
        .pickerStyle(.menu)
        .disabled(isChecking)
        HStack(spacing: 8) {
          Text(checkResultText ?? "Not checked yet.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
          Spacer()
          if isChecking {
            ProgressView()
              .controlSize(.small)
          }
          Button("Check now", action: onCheckNow)
            .disabled(!values.updateCheckEnabled || isChecking)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
      }
      Section("Diagnostics") {
        HStack {
          SettingsFormLabel(
            title: "Logs",
            caption: "Watch events live, copy them, or export a file."
          )
          Spacer()
          Button("Show Logs…") {
            onOpenLogs()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
        Toggle(
          isOn: Binding(
            get: { values.keepLogsAcrossLaunches },
            set: { next in
              if next {
                values.keepLogsAcrossLaunches = true
              } else {
                showsTurnOffConfirm = true
              }
            }
          )
        ) {
          SettingsFormLabel(
            title: "Keep logs across launches",
            caption: "Older entries are compressed and saved to disk, "
              + "window titles included. Off keeps them in memory until you quit."
          )
        }
        Picker(selection: $values.logRotation) {
          ForEach(LogRotation.offered, id: \.self) { rotation in
            Text(rotation.menuName).tag(rotation)
          }
        } label: {
          SettingsFormLabel(
            title: "Rotate archives",
            caption: "Each archive file covers one period within a launch; "
              + "a new launch always starts a new file."
          )
        }
        .pickerStyle(.menu)
        .disabled(!values.keepLogsAcrossLaunches)
        Picker(selection: $values.logRetentionDays) {
          ForEach(LogPersistence.offeredRetentionDays, id: \.self) { days in
            Text("\(days) days").tag(days)
          }
        } label: {
          SettingsFormLabel(
            title: "Keep for",
            caption: "Archives older than this are deleted."
          )
        }
        .pickerStyle(.menu)
        .disabled(!values.keepLogsAcrossLaunches)
        Picker(selection: $values.logDiskLimitGB) {
          ForEach(LogPersistence.offeredDiskLimitsGB, id: \.self) { cap in
            Text("\(cap) GB").tag(cap)
          }
        } label: {
          SettingsFormLabel(
            title: "Disk limit",
            caption: "Oldest archives go first when usage passes this."
          )
        }
        .pickerStyle(.menu)
        .disabled(!values.keepLogsAcrossLaunches)
        HStack {
          SettingsFormLabel(
            title: "Saved logs",
            caption: savedLogsCaption
          )
          Spacer()
          Button("Delete Saved Logs…") {
            showsDeleteConfirm = true
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(savedStatus.launchCount == 0)
        }
      }
      .alert("Delete saved logs?", isPresented: $showsDeleteConfirm) {
        Button("Delete", role: .destructive) {
          onDeleteSavedLogs()
          savedStatus = savedLogs()
        }
        Button("Cancel", role: .cancel) { }
      } message: {
        Text("Delete all saved logs for this build type? This cannot be undone.")
      }
      .alert("Turn off keeping logs?", isPresented: $showsTurnOffConfirm) {
        Button("Delete Saved Logs", role: .destructive) {
          values.keepLogsAcrossLaunches = false
          onDeleteSavedLogs()
          savedStatus = savedLogs()
        }
        Button("Keep Saved Logs") {
          values.keepLogsAcrossLaunches = false
        }
        Button("Cancel", role: .cancel) { }
      } message: {
        Text(
          "Saved logs stay on disk until they age out, or delete them now. "
            + "New entries stay in memory until you quit."
        )
      }
      Section("Permissions") {
        if missing.isEmpty {
          HStack {
            Text("Lanterna has the permissions it needs.")
              .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
          }
        } else {
          Text("Grant the missing permissions, then restart Lanterna.")
            .foregroundStyle(.secondary)
          ForEach(missing) { permission in
            HStack {
              Text(permission.name)
              Spacer()
              Button("Open Settings") {
                _ = opener(permission.settingsURL)
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .settingsBackground()
    .onAppear {
      savedStatus = savedLogs()
    }
    .onChange(of: values) {
      savedStatus = savedLogs()
    }
  }

  // MARK: Private

  @State private var savedStatus = LogPersistence.ArchiveStatus(
    totalBytes: 0,
    launchCount: 0,
    oldest: nil
  )
  @State private var showsDeleteConfirm = false
  @State private var showsTurnOffConfirm = false

  /// What the Saved logs row reads: usage across launches with the
  /// oldest day, or the empty note when nothing is kept.
  private var savedLogsCaption: String {
    let base: String
    if savedStatus.launchCount == 0 {
      base = "No saved logs"
    } else {
      let size = ByteCountFormatter.string(fromByteCount: savedStatus.totalBytes, countStyle: .file)
      let launches = savedStatus.launchCount == 1 ? "1 launch" : "\(savedStatus.launchCount) launches"
      if let oldest = savedStatus.oldest {
        base = "\(size) across \(launches) · oldest \(shortDay(oldest))"
      } else {
        base = "\(size) across \(launches)"
      }
    }
    return base + ". Turning off Keep logs asks whether to delete these too."
  }

  /// The oldest day as a short month and day, read the same way in
  /// every locale.
  private func shortDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
  }

}
