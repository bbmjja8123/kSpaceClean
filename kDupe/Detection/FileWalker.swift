import Foundation
import FileScanner

public actor FileWalker {
    private let fileEnumerator: FileEnumerator

    public init(fileEnumerator: FileEnumerator = FileEnumerator()) {
        self.fileEnumerator = fileEnumerator
    }

    public func walk(target: ScanTarget, controller: ScanController,
                     progress: @escaping @Sendable (FileEnumerator.ScanResult) -> Void) async throws -> [URL] {
        var allFiles: [URL] = []
        let directories = target.directories.map { ($0 as NSString).expandingTildeInPath }

        for dir in directories {
            guard !controller.isCancelled else { return allFiles }
            let url = URL(fileURLWithPath: dir)
            try await fileEnumerator.enumerate(
                root: url,
                progressHandler: { result in
                    guard result.size >= target.minFileSize else { return }
                    allFiles.append(result.url)
                    progress(result)
                },
                cancellationToken: controller.fileToken
            )
        }
        return allFiles
    }
}
