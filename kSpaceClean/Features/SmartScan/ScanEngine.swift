import Foundation
import FileScanner
import DesignSystem
import CoreData

@MainActor
public final class ScanEngine: ObservableObject {
    @Published public private(set) var progress = ScanProgress()
    private let enumerator = FileEnumerator()
    private let hasher = FileHasher()
    private let detector = DuplicateDetector()
    private let cancellationToken = CancellationToken()

    public init() {}

    public func startScan() async {
        progress.state = .scanning
        progress.filesDiscovered = 0

        let scanDirs = [
            URL(filePath: NSHomeDirectory() + "/Library/Caches"),
            URL(filePath: NSHomeDirectory() + "/Library/Application Support"),
            URL(filePath: "/Library/Caches"),
        ]

        for dir in scanDirs {
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }
            do {
                try await enumerator.enumerate(
                    root: dir,
                    progressHandler: { [weak self] result in
                        Task { @MainActor in
                            guard let self = self else { return }
                            self.progress.filesDiscovered += 1
                            self.progress.totalBytes += result.size
                            let category = self.classifyByExtension(result.url)

                            // Persist to Core Data
                            let ctx = CoreDataStack.shared.backgroundContext()
                            ctx.perform {
                                let entry = FileEntry(context: ctx)
                                entry.id = UUID()
                                entry.path = result.url.path
                                entry.size = result.size
                                entry.category = category.rawValue
                                entry.confidence = 0.5
                                try? ctx.save()
                            }
                        }
                    },
                    cancellationToken: cancellationToken
                )
            } catch {
                progress.errors.append(ScanError(path: dir.path, message: error.localizedDescription))
            }
        }

        progress.state = .completed
        progress.finishedAt = Date()
    }

    public func cancel() {
        cancellationToken.cancel()
        progress.state = .cancelled
    }

    // MARK: - Simple extension-based classification (will be replaced by RuleClassifier in Task 5)

    private func classifyByExtension(_ url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        let imageExts: Set<String> = ["jpg","jpeg","png","gif","bmp","tiff","webp","heic","heif"]
        let videoExts: Set<String> = ["mp4","mov","avi","mkv","wmv","flv","webm","m4v"]
        let docExts: Set<String> = ["pdf","doc","docx","xls","xlsx","ppt","pptx","txt","rtf","md"]
        let audioExts: Set<String> = ["mp3","aac","wav","flac","ogg","wma","m4a"]
        let cacheExts: Set<String> = ["cache","tmp","temp","log","swp"]
        let devExts: Set<String> = ["swift","kt","java","py","js","ts","go","rs","c","cpp","h"]

        if imageExts.contains(ext) { return .image }
        if videoExts.contains(ext) { return .video }
        if docExts.contains(ext) { return .document }
        if audioExts.contains(ext) { return .audio }
        if cacheExts.contains(ext) { return .cache }
        if devExts.contains(ext) { return .dev }
        return .other
    }
}
