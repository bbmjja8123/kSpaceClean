import Foundation

public struct ScanProgress: Sendable {
    public enum State: Sendable { case idle, scanning, analysing, completed, cancelled, failed }
    public var state: State = .idle
    public var filesDiscovered: Int = 0
    public var totalBytes: Int64 = 0
    public var currentDirectory: String = ""
    public var errors: [ScanError] = []
    public var finishedAt: Date?
}

public struct ScanError: Identifiable, Sendable {
    public let id = UUID()
    public let path: String
    public let message: String
}
