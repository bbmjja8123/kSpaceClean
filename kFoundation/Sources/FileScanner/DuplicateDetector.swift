import Foundation

public actor DuplicateDetector {
    private var sizeGroups: [Int64: [URL]] = [:]
    private var hashGroups: [String: [URL]] = [:]

    public init() {}

    public func add(file url: URL, size: Int64) {
        sizeGroups[size, default: []].append(url)
    }

    public func candidates() -> [(size: Int64, urls: [URL])] {
        sizeGroups.filter { $0.value.count > 1 }
            .map { ($0.key, $0.value) }
    }

    public func hashGroup(
        _ urls: [URL],
        hasher: FileHasher
    ) async -> [String: [URL]] {
        var groups: [String: [URL]] = [:]
        for url in urls {
            if let hash = try? await hasher.hash(file: url) {
                groups[hash, default: []].append(url)
            }
        }
        return groups.filter { $0.value.count > 1 }
    }
}
