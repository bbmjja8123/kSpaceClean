import SwiftUI

@MainActor
class StartupItemsViewModel: ObservableObject {
    @Published var items: [StartupItem] = []
    @Published var isLoading = false

    private let manager = StartupItemManager()

    func load() async {
        isLoading = true
        let result = await manager.listItems()
        await MainActor.run {
            self.items = result
            self.isLoading = false
        }
    }

    func remove(item: StartupItem) async {
        await manager.remove(item: item)
        await load()
    }
}
