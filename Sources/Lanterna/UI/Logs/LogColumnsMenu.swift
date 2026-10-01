import SwiftUI

/// The columns to show: every fixed one, the context keys under Context,
/// and a way back to the defaults. The last column showing cannot be
/// taken away.
struct LogColumnsMenu: View {

  @Bindable var state: LogWindowState

  var body: some View {
    ForEach(LogColumn.allCases, id: \.self) { column in
      Toggle(column.title, isOn: Binding(
        get: { state.isShown(column) },
        set: { state.setShown(column, $0) }
      ))
      .disabled(!state.canHide(column))
    }
    Menu("Context") {
      let keys = state.availableContextKeys
      if keys.isEmpty {
        Text("No context in these lines")
      }
      ForEach(keys, id: \.self) { key in
        Toggle(key, isOn: Binding(
          get: { state.isShownContext(key) },
          set: { state.setShownContext(key, $0) }
        ))
        .disabled(state.isShownContext(key) && state.shownColumnCount <= 1)
      }
    }
    Divider()
    Button("Reset to Default Columns", action: state.resetColumns)
  }

}
