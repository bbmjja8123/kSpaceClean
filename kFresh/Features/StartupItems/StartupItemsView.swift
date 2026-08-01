import SwiftUI

/// "启动项" (Startup Items) tab — lists each macOS startup item
/// (LaunchAgents, LaunchDaemons, PrefPanes) bucketed by type. Loads
/// via ``StartupItemsViewModel`` and re-renders on toggle / remove.
///
/// ## Pro gating
///
/// `StartupItemsView` itself is NOT wrapped in `.proGate()` — Task 8
/// wires the real Pro gate at the entry point in `AppListView` /
/// `AppDetailView` so this view remains pure rendering (and easy to
/// preview / snapshot test).
struct StartupItemsView: View {
    @StateObject private var viewModel: StartupItemsViewModel

    /// Confirmation dialog state — `nil` means no dialog is shown.
    @State private var removeConfirmation: StartupItem?

    /// Designated init accepts the externally-built view-model so the
    /// app coordinator can inject shared `StartupItemManager`
    /// dependencies for tests and previews.
    init(viewModel: StartupItemsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingStateView(message: "扫描启动项...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(let message):
                EmptyStateView(
                    title: "扫描启动项失败",
                    subtitle: message,
                    icon: "exclamationmark.triangle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let items):
                if items.isEmpty {
                    EmptyStateView(
                        title: "未发现启动项",
                        subtitle: "登录项、Launch Agents、PrefPanes 等未在此 Mac 上出现",
                        icon: "power"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    itemList
                }
            }
        }
        .navigationTitle("启动项")
        .task { await viewModel.load() }
        .confirmationDialog(
            "确认移除？",
            isPresented: Binding(
                get: { removeConfirmation != nil },
                set: { if !$0 { removeConfirmation = nil } }
            ),
            presenting: removeConfirmation
        ) { item in
            Button("移除", role: .destructive) {
                let snapshot = item
                removeConfirmation = nil
                Task { await viewModel.remove(snapshot) }
            }
            Button("取消", role: .cancel) { removeConfirmation = nil }
        } message: { item in
            Text("\(item.name) 将被备份到 ~/Library/Application Support/app.kraftly.kfresh/Backups/StartupItems/")
        }
    }

    /// The grouped list view — one `Section` per `StartupItemType`,
    /// each populated with ``StartupItemRowView`` rows.
    private var itemList: some View {
        List {
            ForEach(viewModel.groupedByType, id: \.0) { type, items in
                Section(header: Text(type.displayName)) {
                    ForEach(items) { item in
                        StartupItemRowView(
                            item: item,
                            onToggle: {
                                Task { await viewModel.toggle(item) }
                            },
                            onRemove: {
                                removeConfirmation = item
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

/// Display name for ``StartupItemType`` used as the section header in
/// ``StartupItemsView``. Handles all four cases (the `.prefPane` case
/// was introduced after the brief was written — using only three cases
/// would trigger a switch-exhaustiveness compile error).
extension StartupItemType {
    /// Localized display name — Chinese for `.loginItem`, English
    /// (canonical Apple naming) for the three launchd-driven cases.
    var displayName: String {
        switch self {
        case .loginItem:
            return "登录项"
        case .launchAgent:
            return "Launch Agents"
        case .launchDaemon:
            return "Launch Daemons"
        case .prefPane:
            return "PrefPanes"
        }
    }
}
