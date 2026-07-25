import Foundation

public actor RawJPEGPairDetector {
    private let rawExtensions: Set<String> = ["raf", "cr2", "nef", "arw", "dng", "orf"]
    private let jpegExtensions: Set<String> = ["jpg", "jpeg", "jpe"]

    public init() {}

    public func detect(_ urls: [URL], controller: ScanController) -> [DuplicateGroup] {
        let files = Dictionary(grouping: urls) { url -> String in
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            return name
        }

        var groups: [DuplicateGroup] = []
        for (baseName, group) in files {
            guard !controller.isCancelled else { return groups }
            let raws = group.filter { rawExtensions.contains($0.pathExtension.lowercased()) }
            let jpegs = group.filter { jpegExtensions.contains($0.pathExtension.lowercased()) }
            guard !raws.isEmpty, !jpegs.isEmpty else { continue }

            let all = raws + jpegs
            let totalSize = all.reduce(0) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int64) ?? 0) }
            let items = all.map { FileItem(id: UUID(), url: $0, size: 0, modificationDate: Date(), hash: nil) }
            groups.append(DuplicateGroup(
                id: UUID(), category: .rawJPEG, totalSize: totalSize, fileCount: all.count, files: items
            ))
        }
        return groups
    }
}
