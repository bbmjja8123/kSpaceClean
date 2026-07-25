import Foundation

public actor LargeFileDetector {
    private let threshold: Int64

    public init(threshold: Int64 = 1024 * 1024 * 1024) { // 1GB
        self.threshold = threshold
    }

    public func detect(_ urls: [URL], controller: ScanController) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []
        for url in urls {
            guard !controller.isCancelled else { return groups }
            guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64,
                  size >= threshold else { continue }
            let item = FileItem(id: UUID(), url: url, size: size, modificationDate: Date(), hash: nil)
            groups.append(DuplicateGroup(
                id: UUID(), category: .largeFile, totalSize: size, fileCount: 1, files: [item]
            ))
        }
        return groups
    }
}
