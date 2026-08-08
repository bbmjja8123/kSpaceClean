import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pairs RAW and JPEG neighbors by directory, filename stem, and EXIF capture time.
public actor RawJPEGPairDetector {
    private struct PairKey: Hashable {
        let directory: String
        let stem: String
    }

    private let rawExtensions: Set<String> = [
        "3fr", "arw", "cr2", "cr3", "dcr", "dng", "erf", "fff", "iiq",
        "k25", "kdc", "mef", "mos", "mrw", "nef", "nrw", "orf", "pef",
        "raf", "raw", "rw2", "rwl", "sr2", "srf", "srw", "x3f",
    ]
    private let jpegExtensions: Set<String> = ["jpg", "jpeg", "jpe"]
    private let exifTolerance: TimeInterval
    private let exifDateFormatter: DateFormatter

    public init(exifTolerance: TimeInterval = 2) {
        self.exifTolerance = max(0, exifTolerance)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        exifDateFormatter = formatter
    }

    /// Loads file metadata and detects RAW/JPEG pairs.
    public func detect(_ urls: [URL], controller: ScanController) -> [DuplicateGroup] {
        detect(files: urls.compactMap(makeFileItem), controller: controller)
    }

    /// Returns one group per pair and leaves the keep/delete choice to the UI.
    public func detect(files: [FileItem], controller: ScanController) -> [DuplicateGroup] {
        let relevantFiles = files.filter {
            let fileExtension = $0.url.pathExtension.lowercased()
            return rawExtensions.contains(fileExtension) || jpegExtensions.contains(fileExtension)
        }
        let buckets = Dictionary(grouping: relevantFiles) { file in
            PairKey(
                directory: file.url.deletingLastPathComponent().standardizedFileURL.path,
                stem: file.url.deletingPathExtension().lastPathComponent.lowercased()
            )
        }

        var groups: [DuplicateGroup] = []
        for bucket in buckets.values {
            guard !controller.isCancelled, !Task.isCancelled else { return groups }
            let rawFiles = bucket
                .filter { rawExtensions.contains($0.url.pathExtension.lowercased()) }
                .sorted { $0.url.path < $1.url.path }
            var availableJPEGs = bucket
                .filter { jpegExtensions.contains($0.url.pathExtension.lowercased()) }
                .sorted { $0.url.path < $1.url.path }

            for rawFile in rawFiles {
                guard !controller.isCancelled, !Task.isCancelled else { return groups }
                guard let match = bestJPEG(for: rawFile, candidates: availableJPEGs) else { continue }
                availableJPEGs.remove(at: match.index)
                let jpegFile = match.file
                groups.append(DuplicateGroup(
                    id: UUID(),
                    category: .rawJPEG,
                    totalSize: 0,
                    fileCount: 2,
                    files: [rawFile, jpegFile],
                    categoryEvidence: .rawJPEGPair(
                        rawFile: rawFile,
                        jpegFile: jpegFile,
                        exifMatch: match.exifMatch
                    )
                ))
            }
        }

        return groups.sorted {
            ($0.files.first?.url.path ?? "") < ($1.files.first?.url.path ?? "")
        }
    }

    func captureDate(of url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary,
              let value = exif[kCGImagePropertyExifDateTimeOriginal] as? String else {
            return nil
        }
        return exifDateFormatter.date(from: value)
    }

    private func bestJPEG(
        for rawFile: FileItem,
        candidates: [FileItem]
    ) -> (index: Int, file: FileItem, exifMatch: Bool)? {
        let rawCaptureDate = captureDate(of: rawFile.url)
        var possibleMatches: [(index: Int, file: FileItem, exifMatch: Bool, distance: TimeInterval)] = []

        for (index, jpeg) in candidates.enumerated() {
            let jpegCaptureDate = captureDate(of: jpeg.url)
            let exifMatch: Bool
            if let rawCaptureDate, let jpegCaptureDate {
                let difference = abs(rawCaptureDate.timeIntervalSince(jpegCaptureDate))
                guard difference <= exifTolerance else { continue }
                exifMatch = true
            } else {
                exifMatch = false
            }
            let modificationDistance = abs(
                rawFile.modificationDate.timeIntervalSince(jpeg.modificationDate)
            )
            possibleMatches.append((index, jpeg, exifMatch, modificationDistance))
        }

        return possibleMatches.min {
            if $0.exifMatch != $1.exifMatch { return $0.exifMatch && !$1.exifMatch }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.file.url.path < $1.file.url.path
        }.map { ($0.index, $0.file, $0.exifMatch) }
    }

    private func makeFileItem(_ url: URL) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .totalFileAllocatedSizeKey,
            .isRegularFileKey,
        ]), values.isRegularFile == true else {
            return nil
        }
        return FileItem(
            id: UUID(),
            url: url,
            size: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? .distantPast,
            creationDate: values.creationDate,
            physicalSize: values.totalFileAllocatedSize.map(Int64.init),
            fileType: UTType(filenameExtension: url.pathExtension)
        )
    }
}
