import Foundation
import SwiftUI

@MainActor
@Observable
public final class ScanViewModel {
    public var progress = ScanProgress()
    public var scanResults: [FileEntry] = []
    private let engine = ScanEngine()

    public init() {}

    public func startScan() {
        Task {
            await engine.startScan()
            // results are persisted to Core Data by the engine
        }
    }

    public func cancelScan() {
        engine.cancel()
    }
}
