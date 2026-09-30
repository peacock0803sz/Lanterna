import Combine

/// The shared values behind the settings tabs.
///
/// One owner for every tab, so each edit reports the whole snapshot once.
/// Assigning an equal value reports nothing.
@MainActor
final class SettingsModel: ObservableObject {

  // MARK: Lifecycle

  init(values: SettingsValues, onChange: @escaping (SettingsValues) -> Void) {
    self.values = values
    self.onChange = onChange
  }

  // MARK: Internal

  @Published var values: SettingsValues {
    didSet {
      if oldValue != values {
        onChange(values)
      }
    }
  }

  // MARK: Private

  private let onChange: (SettingsValues) -> Void

}
