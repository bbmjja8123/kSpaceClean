import Accelerate
import Foundation
#if canImport(Vision)
import Vision
#endif

public actor PerceptualDetector {
    public init() {}

    public func detect(_ urls: [URL], controller: ScanController) async throws -> [DuplicateGroup] {
        guard #available(macOS 14, *) else { return [] }
        #if canImport(Vision)
        var hashDict: [Data: [URL]] = [:]
        for url in urls {
            guard !controller.isCancelled else { return [] }
            guard let hash = try await imageHash(for: url) else { continue }
            hashDict[hash, default: []].append(url)
        }

        var groups: [DuplicateGroup] = []
        for (_, files) in hashDict where files.count > 1 {
            let items = files.map { FileItem(id: UUID(), url: $0, size: 0, modificationDate: Date(), hash: nil) }
            groups.append(DuplicateGroup(id: UUID(), category: .perceptual, totalSize: 0, fileCount: files.count, files: items))
        }
        return groups
        #else
        return []
        #endif
    }

    @available(macOS 14, *)
    private func imageHash(for url: URL) async -> Data? {
        #if canImport(Vision)
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let request = VNGenerateImageHashRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])
        return request.results?.first?.imageHashData
        #else
        return nil
        #endif
    }
}
