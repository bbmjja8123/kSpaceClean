import Foundation

/// Produces a flat, size-sorted list of files above a configurable threshold.
public actor LargeFileDetector {
    private let threshold: Int64

    public init(threshold: Int64 = 100 * 1024 * 1024) {
        self.threshold = max(0, threshold)
    }

    /// Loads metadata and returns large files without wrapping each file in a duplicate group.
    public func detect(_ urls: [URL], controller: ScanController) -> [FileItem] {
        detect(files: urls.compactMap(FileItem.fromMetadata), controller: controller)
    }

    /// Filters previously enumerated file metadata without additional disk I/O.
    public func detect(files: [FileItem], controller: ScanController) -> [FileItem] {
        var results: [FileItem] = []
        for file in files {
            guard !controller.isCancelled, !Task.isCancelled else { return results }
            if file.size >= threshold {
                results.append(file)
            }
        }
        return results.sorted {
            if $0.size == $1.size {
                return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
            }
            return $0.size > $1.size
        }
    }

}
