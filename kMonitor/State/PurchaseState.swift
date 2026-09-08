import Foundation
import Combine

/// UI-owned, main-actor-isolated state for the Pro entitlement.
@MainActor
public final class PurchaseState: ObservableObject {
    @Published public private(set) var isPro: Bool = false
    @Published public private(set) var lastError: String?

    public init() {}

    public func update(isPro: Bool) {
        self.isPro = isPro
    }

    public func recordError(_ message: String) {
        self.lastError = message
    }

    public func clearError() {
        self.lastError = nil
    }
}