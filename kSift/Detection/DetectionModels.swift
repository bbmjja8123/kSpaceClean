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
    private var _isPaused = false

    public var isCancelled: Bool { token.isCancelled }
    public var isPaused: Bool { _isPaused }

    public init() {}

    public func cancel() { token.cancel() }
    public func pause() { _isPaused = true }
    public func resume() { _isPaused = false }

    public var fileToken: CancellationToken { token }
}
