import SwiftUI

/// Transient undo toast shown after a successful uninstall.
///
/// Task 4 fills in the countdown + undo affordance; this is the placeholder
/// that keeps the Task 3 detail flow compiling.
struct UninstallToast: View {
    struct State: Identifiable {
        let id = UUID()
        let recordID: UUID
        let appName: String
        let appSize: Int64
    }

    let state: State
    let onUndo: () -> Void

    var body: some View {
        Text("Stub — Task 4")
            .padding()
    }
}
