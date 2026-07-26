import Foundation

public protocol SnapshotWriterProtocol: Sendable {
    func write(_ snapshot: SharedSnapshot) throws
    func read() throws -> SharedSnapshot?
}

public enum SnapshotWriterError: Error, LocalizedError, Sendable {
    case directoryUnavailable
    case encodingFailed
    case writeFailed(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .directoryUnavailable: return "Snapshot directory is unavailable"
        case .encodingFailed: return "Failed to encode snapshot"
        case .writeFailed(let message): return "Failed to write snapshot: \(message)"
        case .readFailed(let message): return "Failed to read snapshot: \(message)"
        }
    }
}

public final class SnapshotWriter: SnapshotWriterProtocol, @unchecked Sendable {
    private let directory: URL
    private let filename: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL, filename: String = "snapshot.json") {
        self.directory = directory
        self.filename = filename
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
    }

    public func write(_ snapshot: SharedSnapshot) throws {
        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            throw SnapshotWriterError.encodingFailed
        }
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let finalURL = directory.appendingPathComponent(filename)
        let tempURL = directory.appendingPathComponent("\(filename).tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            throw SnapshotWriterError.writeFailed(String(describing: error))
        }
        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: finalURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw SnapshotWriterError.writeFailed(String(describing: error))
        }
    }

    public func read() throws -> SharedSnapshot? {
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(SharedSnapshot.self, from: data)
        } catch {
            throw SnapshotWriterError.readFailed(String(describing: error))
        }
    }
}
