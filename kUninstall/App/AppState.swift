import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var phase: AppPhase = .loading
    @Published var scanProgress: Double = 0
    @Published var errorMessage: String?

    enum AppPhase {
        case loading
        case scanning
        case ready
        case error
    }
}
