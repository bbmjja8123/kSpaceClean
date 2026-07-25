import Foundation

public extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    var fileSize: Int64 {
        guard let values = try? resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey]) else {
            return 0
        }
        return Int64(values.fileSize ?? values.fileAllocatedSize ?? 0)
    }

    var isPackage: Bool {
        (try? resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
    }
}
