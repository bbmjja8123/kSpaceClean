import Foundation
import FileScanner

public struct DetectionProgress: Sendable {
    public let phase: ScanPhase
    public let currentItem: String?
    public let itemsProcessed: Int
    public let totalItems: Int

    public init(phase: ScanPhase, currentItem: String? = nil, itemsProcessed: Int = 0, totalItems: Int = 0) {
        self.phase = phase
        self.currentItem = currentItem
        self.itemsProcessed = itemsProcessed
        self.totalItems = totalItems
    }
}

public final class ScanController: @unchecked Sendable {
    private let token = CancellationToken()

    public var isCancelled: Bool { token.isCancelled }

    public init() {}

    public func cancel() { token.cancel() }

    public var fileToken: CancellationToken { token }
}
