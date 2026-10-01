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
  @Binding var values: SettingsValues

  let version: DisplayedVersion
  let missing: [MissingPermission]
  let opener: SettingsOpener
  var checkResultText: String?
  var isChecking = false
  var onCheckNow: () -> Void = { }
  var onOpenLogs: () -> Void = { }

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
  }
}
