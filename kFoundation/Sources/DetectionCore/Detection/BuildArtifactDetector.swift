import Foundation

/// Detects developer build artifacts and collapses files under the same artifact root.
public actor BuildArtifactDetector {
    struct MatchKey: Hashable {
        let root: URL
        let pattern: BuildPattern
    }

    public init() {}

    /// Loads file metadata before applying build-artifact rules.
    public func detect(_ urls: [URL], controller: ScanController) -> [DuplicateGroup] {
        detect(files: urls.compactMap(FileItem.fromMetadata), controller: controller)
    }

    /// Groups matched files by artifact root so directories such as node_modules appear once.
    public func detect(files: [FileItem], controller: ScanController) -> [DuplicateGroup] {
        var buckets: [MatchKey: [FileItem]] = [:]
        for file in files {
            guard !controller.isCancelled, !Task.isCancelled else { return makeGroups(buckets) }
            guard let match = match(for: file.url) else { continue }
            buckets[match, default: []].append(file)
        }
        return makeGroups(buckets)
    }

    func match(for url: URL) -> MatchKey? {
        let components = url.standardizedFileURL.pathComponents
        let lowercased = components.map { $0.lowercased() }

        if let index = lowercased.firstIndex(of: "node_modules") {
            return MatchKey(root: rootURL(components, through: index), pattern: .nodeModules)
        }
        if let index = lowercased.firstIndex(of: "deriveddata") {
            return MatchKey(root: rootURL(components, through: index), pattern: .xcodeDerivedData)
        }
        if let index = lowercased.firstIndex(of: ".build") {
            return MatchKey(root: rootURL(components, through: index), pattern: .swiftBuild)
        }
        if let index = lowercased.firstIndex(of: ".swiftpm") {
            return MatchKey(root: rootURL(components, through: index), pattern: .swiftPM)
        }
        if let index = lowercased.firstIndex(of: "xcuserdata") {
            return MatchKey(root: rootURL(components, through: index), pattern: .xcodeUserData)
        }
        if let index = lowercased.firstIndex(of: "pods") {
            return MatchKey(root: rootURL(components, through: index), pattern: .cocoaPods)
        }
        if let index = lowercased.firstIndex(of: ".gradle") {
            return MatchKey(root: rootURL(components, through: index), pattern: .gradle)
        }
        if let index = lowercased.firstIndex(of: ".next") {
            return MatchKey(root: rootURL(components, through: index), pattern: .nextCache)
        }
        if let index = lowercased.firstIndex(of: ".cache") {
            return MatchKey(root: rootURL(components, through: index), pattern: .cache)
        }
        if let index = pairedComponentIndex(first: "carthage", second: "build", in: lowercased) {
            return MatchKey(root: rootURL(components, through: index + 1), pattern: .carthageBuild)
        }
        if let index = pairedComponentIndex(first: "target", second: "debug", in: lowercased)
            ?? pairedComponentIndex(first: "target", second: "release", in: lowercased) {
            return MatchKey(root: rootURL(components, through: index + 1), pattern: .rustTarget)
        }
        if let index = lowercased.firstIndex(of: "vendor") {
            return MatchKey(root: rootURL(components, through: index), pattern: .goVendor)
        }
        if let index = lowercased.firstIndex(where: { $0 == "build" || $0 == "dist" }) {
            return MatchKey(root: rootURL(components, through: index), pattern: .genericBuild)
        }

        switch url.pathExtension.lowercased() {
        case "o":
            return MatchKey(root: url.standardizedFileURL, pattern: .objectFile)
        case "pyc":
            return MatchKey(root: url.standardizedFileURL, pattern: .pythonBytecode)
        case "class":
            return MatchKey(root: url.standardizedFileURL, pattern: .javaClass)
        case "a", "lib", "obj":
            return MatchKey(root: url.standardizedFileURL, pattern: .staticLibrary)
        default:
            return nil
        }
    }

    private func makeGroups(_ buckets: [MatchKey: [FileItem]]) -> [DuplicateGroup] {
        buckets.map { key, files in
            let sortedFiles = files.sorted { $0.url.path < $1.url.path }
            let totalSize = sortedFiles.reduce(Int64(0)) { partial, file in
                let addition = partial.addingReportingOverflow(file.size)
                return addition.overflow ? Int64.max : addition.partialValue
            }
            return DuplicateGroup(
                id: UUID(),
                category: .buildArtifact,
                totalSize: totalSize,
                fileCount: sortedFiles.count,
                files: sortedFiles,
                categoryEvidence: .buildArtifact(pattern: key.pattern)
            )
        }
        .sorted {
            if $0.totalSize == $1.totalSize {
                return ($0.files.first?.url.path ?? "") < ($1.files.first?.url.path ?? "")
            }
            return $0.totalSize > $1.totalSize
        }
    }

    private func pairedComponentIndex(
        first: String,
        second: String,
        in components: [String]
    ) -> Int? {
        guard components.count > 1 else { return nil }
        return components.indices.dropLast().first {
            components[$0] == first && components[$0 + 1] == second
        }
    }

    private func rootURL(_ components: [String], through index: Int) -> URL {
        URL(
            fileURLWithPath: NSString.path(withComponents: Array(components.prefix(index + 1))),
            isDirectory: true
        ).standardizedFileURL
    }

}
