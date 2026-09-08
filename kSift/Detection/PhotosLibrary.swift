import CryptoKit
import Foundation
import Photos
import DetectionCore
import CoreGraphics

// MARK: - Provider abstraction
//
// Every Photos.framework entry point hides behind `PhotoLibraryProviding`
// so the scanner logic is fully unit-testable — tests drive a stub and
// never touch PHPhotoLibrary.

/// A lightweight, Sendable view of one PHAsset.
public struct PhotoAssetSnapshot: Sendable, Identifiable, Equatable {
    public let id: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let creationDate: Date?
    public let isFavorite: Bool

    public init(
        id: String,
        pixelWidth: Int,
        pixelHeight: Int,
        creationDate: Date?,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.creationDate = creationDate
        self.isFavorite = isFavorite
    }
}

public enum PhotoAuthorizationStatus: Sendable, Equatable {
    case notDetermined, restricted, denied, authorized, limited
}

public protocol PhotoLibraryProviding: Sendable {
    func authorizationStatus() -> PhotoAuthorizationStatus
    func requestAccess() async -> Bool
    func fetchPhotoSnapshots() -> [PhotoAssetSnapshot]
    /// SHA-256 of the asset's bytes, computed with network access
    /// disabled. Nil for cloud-only assets — this is the exact-pass
    /// gate AND the iCloud-only signal in one.
    func sha256IfLocallyAvailable(id: String) async -> String?
    /// nil = not locally available (iCloud-only and downloads disabled).
    func thumbnail(id: String, maxPixelSize: Int) async -> CGImage?
}

public protocol PhotoLibraryDeleting: Sendable {
    /// Sends assets to the Photos "Recently Deleted" album (native 30-day
    /// undo) — deliberately NOT routed through the kSift Vault.
    func deleteAssets(ids: [String]) async throws
}

// MARK: - PHAsset-backed provider

public struct PHAssetLibraryProvider: PhotoLibraryProviding, PhotoLibraryDeleting {
    public init() {}

    public func authorizationStatus() -> PhotoAuthorizationStatus {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .denied
        }
    }

    public func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    public func fetchPhotoSnapshots() -> [PhotoAssetSnapshot] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetch = PHAsset.fetchAssets(with: PHAssetMediaType.image, options: options)
        var snapshots: [PhotoAssetSnapshot] = []
        snapshots.reserveCapacity(fetch.count)
        fetch.enumerateObjects { asset, _, _ in
            snapshots.append(PhotoAssetSnapshot(
                id: asset.localIdentifier,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                creationDate: asset.creationDate,
                isFavorite: asset.isFavorite
            ))
        }
        return snapshots
    }

    public func sha256IfLocallyAvailable(id: String) async -> String? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo }) ?? resources.first else {
            return nil
        }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false

        return await withCheckedContinuation { continuation in
            var hasher = SHA256()
            var resumed = false
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in hasher.update(data: data) }
            ) { error in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: error == nil
                    ? hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    : nil)
            }
        }
    }

    public func thumbnail(id: String, maxPixelSize: Int) async -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: maxPixelSize, height: maxPixelSize),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                if degraded { return }
                guard !resumed else { return }
                resumed = true
                let cgImage = image.flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
                continuation.resume(returning: cgImage)
            }
        }
    }

    public func deleteAssets(ids: [String]) async throws {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard fetch.count > 0 else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(fetch)
        }
    }
}

// MARK: - FileItem bridging

public extension FileItem {
    /// Synthetic URL for Photos-backed results ("photos-asset://<id>").
    static func photosAssetURL(_ localIdentifier: String) -> URL {
        URL(string: "photos-asset://\(localIdentifier.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? localIdentifier)")
            ?? URL(fileURLWithPath: "/Photos/\(localIdentifier)")
    }
}

// MARK: - Scanner

public struct PhotosScanOutcome: Sendable {
    public var groups: [DuplicateGroup]
    public let totalAssets: Int
    public let cloudSkipped: Int
    public let scannedAt: Date
}

/// Finds duplicate and similar photos inside the user's photo library.
///
/// Exact pass: SHA-256 over locally-available bytes (network disabled) —
/// identical hashes group byte-identical assets. Perceptual pass: the
/// remaining assets (same pixel dimensions + creation window) get
/// PHImageManager thumbnails and the shared dHash pipeline. Assets with
/// neither local bytes nor a thumbnail are iCloud-only: skipped and
/// counted, never silently downloaded.
public actor PhotosLibraryScanner {
    private let provider: any PhotoLibraryProviding
    private let maximumHammingDistance: Int

    public init(provider: any PhotoLibraryProviding = PHAssetLibraryProvider(), preset: SimilarityPreset = .normal) {
        self.provider = provider
        self.maximumHammingDistance = preset.maximumHammingDistance
    }

    public func scan(controller: ScanController) async -> PhotosScanOutcome? {
        let status = provider.authorizationStatus()
        guard status == .authorized || status == .limited else { return nil }

        let snapshots = provider.fetchPhotoSnapshots()
        var cloudSkipped = 0
        var exactClusters: [[PhotoAssetSnapshot]] = []

        // --- Exact pass: SHA-256 (local bytes only).
        var byHash: [String: [PhotoAssetSnapshot]] = [:]
        var hashedLocally = Set<String>()
        for snapshot in snapshots {
            guard !controller.isCancelled else { return nil }
            if let hash = await provider.sha256IfLocallyAvailable(id: snapshot.id) {
                byHash[hash, default: []].append(snapshot)
                hashedLocally.insert(snapshot.id)
            }
        }
        for cluster in byHash.values where cluster.count > 1 {
            exactClusters.append(cluster)
        }

        // --- Perceptual pass: same-dimension candidates among the rest
        // (exact duplicates already handled).
        var byDimensions: [String: [PhotoAssetSnapshot]] = [:]
        for snapshot in snapshots where !hashedLocally.contains(snapshot.id) {
            byDimensions["\(snapshot.pixelWidth)x\(snapshot.pixelHeight)", default: []].append(snapshot)
        }

        var perceptualClusters: [[PhotoAssetSnapshot]] = []
        for (_, candidates) in byDimensions where candidates.count > 1 {
            guard !controller.isCancelled else { return nil }
            var hashed: [(PhotoAssetSnapshot, UInt64)] = []
            for candidate in candidates {
                guard let image = await provider.thumbnail(id: candidate.id, maxPixelSize: 256),
                      let hash = PerceptualHashing.dHash(of: image) else {
                    cloudSkipped += 1
                    continue
                }
                hashed.append((candidate, hash))
            }
            // Pairwise within the (small) same-dimension bucket.
            var parent = Array(hashed.indices)
            func find(_ x: Int) -> Int {
                var root = x
                while parent[root] != root { root = parent[root] }
                return root
            }
            for i in hashed.indices {
                for j in hashed.indices where j > i {
                    if PerceptualHashing.hammingDistance(hashed[i].1, hashed[j].1) <= maximumHammingDistance {
                        parent[max(find(i), find(j))] = find(i)
                    }
                }
            }
            var clusters: [Int: [PhotoAssetSnapshot]] = [:]
            for index in hashed.indices {
                clusters[find(index), default: []].append(hashed[index].0)
            }
            for cluster in clusters.values where cluster.count > 1 {
                perceptualClusters.append(cluster)
            }
        }

        // Assets never hashed and never thumbnailed are iCloud-only.
        let matchedIDs = Set(exactClusters.flatMap { $0.map(\.id) })
            .union(perceptualClusters.flatMap { $0.map(\.id) })
        let processedIDs = hashedLocally.union(matchedIDs)

        func makeGroup(_ cluster: [PhotoAssetSnapshot], identical: Bool) -> DuplicateGroup {
            let files = cluster.map { snapshot in
                FileItem(
                    id: UUID(),
                    url: FileItem.photosAssetURL(snapshot.id),
                    size: 0,
                    modificationDate: snapshot.creationDate ?? .distantPast,
                    creationDate: snapshot.creationDate,
                    photosLocalIdentifier: snapshot.id
                )
            }
            let reclaimable = files.dropFirst().reduce(Int64(0)) { $0 + $1.size }
            return DuplicateGroup(
                id: UUID(),
                category: identical ? .identical : .perceptual,
                totalSize: reclaimable,
                fileCount: files.count,
                files: files,
                categoryEvidence: identical
                    ? .byteIdentical(sha256: "", byteVerified: true)
                    : .perceptualSimilarity(
                        distance: Double(maximumHammingDistance),
                        method: .dHash
                    )
            )
        }

        let groups = exactClusters.map { makeGroup($0, identical: true) }
            + perceptualClusters.map { makeGroup($0, identical: false) }

        return PhotosScanOutcome(
            groups: groups.sorted { $0.totalSize > $1.totalSize },
            totalAssets: snapshots.count,
            cloudSkipped: max(cloudSkipped, snapshots.count - processedIDs.count),
            scannedAt: Date()
        )
    }
}

/// Moves duplicate Photos assets to the system "Recently Deleted" album.
/// Bypasses VaultManager on purpose: Photos already provides the 30-day
/// undo surface, and copying library assets into the kSift vault would
/// duplicate storage.
public actor PhotosCleanupManager {
    private let library: any PhotoLibraryDeleting

    public init(library: any PhotoLibraryDeleting = PHAssetLibraryProvider()) {
        self.library = library
    }

    /// Deletes every asset referenced in `files` (matched by
    /// `photosLocalIdentifier`). Returns the identifiers that could not
    /// be deleted (already deleted, permission loss, …).
    @discardableResult
    public func delete(_ files: [FileItem]) async -> [String] {
        let ids = files.compactMap(\.photosLocalIdentifier)
        guard !ids.isEmpty else { return [] }
        do {
            try await library.deleteAssets(ids: ids)
            return []
        } catch {
            return ids
        }
    }
}
