import Darwin
import Foundation

/// Annotates byte-identical groups whose files share APFS physical blocks.
public actor APFSCloneDetector {
    struct PhysicalExtent: Equatable, Sendable {
        let start: Int64
        let length: Int64

        var end: Int64 { start + length }
    }

    public init() {}

    /// Marks APFS clone members and corrects reclaimable size for shared blocks.
    public func annotate(_ groups: [DuplicateGroup]) -> [DuplicateGroup] {
        groups.map(annotate)
    }

    func inode(of url: URL) -> UInt64? {
        var fileInfo = stat()
        let status: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.lstat(path, &fileInfo)
        }
        guard status == 0 else { return nil }
        return UInt64(fileInfo.st_ino)
    }

    func physicalExtents(of url: URL) -> [PhysicalExtent]? {
        let descriptor: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC)
        }
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var fileInfo = stat()
        guard Darwin.fstat(descriptor, &fileInfo) == 0, fileInfo.st_size > 0 else {
            return nil
        }

        let fileSize = Int64(fileInfo.st_size)
        var logicalOffset: Int64 = 0
        var extents: [PhysicalExtent] = []

        while logicalOffset < fileSize {
            var mapping = log2phys()
            mapping.l2p_contigbytes = fileSize - logicalOffset
            mapping.l2p_devoffset = logicalOffset

            guard Darwin.fcntl(descriptor, F_LOG2PHYS_EXT, &mapping) == 0 else {
                return nil
            }

            let contiguousBytes = min(Int64(mapping.l2p_contigbytes), fileSize - logicalOffset)
            guard contiguousBytes > 0 else { return nil }

            let deviceOffset = Int64(mapping.l2p_devoffset)
            if deviceOffset >= 0 {
                extents.append(PhysicalExtent(start: deviceOffset, length: contiguousBytes))
            }
            logicalOffset += contiguousBytes
        }

        return extents.sorted { $0.start < $1.start }
    }

    func sharePhysicalBlocks(_ lhs: [PhysicalExtent], _ rhs: [PhysicalExtent]) -> Bool {
        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < lhs.count, rightIndex < rhs.count {
            let left = lhs[leftIndex]
            let right = rhs[rightIndex]

            if left.start < right.end, right.start < left.end {
                return true
            }
            if left.end <= right.start {
                leftIndex += 1
            } else {
                rightIndex += 1
            }
        }
        return false
    }

    private func annotate(_ group: DuplicateGroup) -> DuplicateGroup {
        guard group.category == .identical, group.files.count > 1 else { return group }

        let files = group.files
        let inodes = files.map { $0.inode ?? inode(of: $0.url) }
        let extents = files.map { physicalExtents(of: $0.url) }
        var parents = Array(files.indices)
        var cloneIndices = Set<Int>()

        func root(of index: Int) -> Int {
            var current = index
            while parents[current] != current {
                current = parents[current]
            }
            return current
        }

        func join(_ lhs: Int, _ rhs: Int) {
            let leftRoot = root(of: lhs)
            let rightRoot = root(of: rhs)
            if leftRoot != rightRoot {
                parents[rightRoot] = leftRoot
            }
        }

        for leftIndex in files.indices {
            for rightIndex in files.indices where rightIndex > leftIndex {
                guard let leftInode = inodes[leftIndex],
                      let rightInode = inodes[rightIndex],
                      leftInode != rightInode,
                      let leftExtents = extents[leftIndex],
                      let rightExtents = extents[rightIndex],
                      sharePhysicalBlocks(leftExtents, rightExtents) else {
                    continue
                }

                cloneIndices.insert(leftIndex)
                cloneIndices.insert(rightIndex)
                join(leftIndex, rightIndex)
            }
        }

        guard !cloneIndices.isEmpty else { return group }

        let physicalCopies = Set(files.indices.map { root(of: $0) }).count
        let size = files.first?.size ?? 0
        let reclaimable = size.multipliedReportingOverflow(by: Int64(max(physicalCopies - 1, 0)))
        let hash = files.first?.hash ?? ""
        let markedFiles = files.enumerated().map { index, file in
            FileItem(
                id: file.id,
                url: file.url,
                size: file.size,
                modificationDate: file.modificationDate,
                creationDate: file.creationDate,
                hash: file.hash,
                fingerprint: file.fingerprint,
                inode: inodes[index],
                isAPFSClone: cloneIndices.contains(index),
                physicalSize: file.physicalSize,
                fileType: file.fileType
            )
        }

        return DuplicateGroup(
            id: group.id,
            category: group.category,
            totalSize: reclaimable.overflow ? Int64.max : reclaimable.partialValue,
            fileCount: group.fileCount,
            files: markedFiles,
            categoryEvidence: .apfsClone(sha256: hash),
            similarity: group.similarity,
            scanTimestamp: group.scanTimestamp
        )
    }
}
