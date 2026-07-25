import SwiftUI

@MainActor
class DeepCleanViewModel: ObservableObject {
    @Published var groups: [DeepCleanEngine.CleanGroup] = []
    @Published var isScanning = false
    @Published var hasFDA = false

    private let engine = DeepCleanEngine()
    private let authorizer = FDAuthorizer()

    func checkFDA() async {
        let result = await authorizer.checkFDA()
        await MainActor.run { self.hasFDA = result }
    }

    func scan() async {
        isScanning = true
        let result = await engine.scanSystemWideResidues()
        await MainActor.run {
            self.groups = result
            self.isScanning = false
        }
    }

    func clean() async -> Int {
        let freed = await engine.cleanSelected(groups)
        await scan()
        return freed
    }
}
