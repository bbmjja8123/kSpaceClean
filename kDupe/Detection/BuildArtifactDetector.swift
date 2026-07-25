import Foundation

public actor BuildArtifactDetector {
    private let artifactPatterns: [String] = [
        ".o$", ".pyc$", ".class$", ".a$", ".lib$", ".obj$",
        "node_modules/", ".build/", "DerivedData/", "Pods/",
        ".gradle/", "build/", "dist/", ".next/"
    ]

    public init() {}

    public func detect(_ urls: [URL], controller: ScanController) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []
        for url in urls {
            guard !controller.isCancelled else { return groups }
            let path = url.path
            guard artifactPatterns.contains(where: { path.range(of: $0, options: .regularExpression) != nil }),
                  let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64 else { continue }
            let item = FileItem(id: UUID(), url: url, size: size, modificationDate: Date(), hash: nil)
            groups.append(DuplicateGroup(
                id: UUID(), category: .buildArtifact, totalSize: size, fileCount: 1, files: [item]
            ))
        }
        return groups
    }
}
