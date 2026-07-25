import Foundation

@MainActor
class FDAGuideController: ObservableObject {
    @Published var showGuide = false
    private let authorizer = FDAuthorizer()

    func checkAndGuide() {
        Task {
            let hasFDA = await authorizer.checkFDA()
            if !hasFDA {
                showGuide = true
            }
        }
    }
}
