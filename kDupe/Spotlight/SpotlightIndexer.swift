import Foundation

#if canImport(CoreSpotlight)
@preconcurrency import CoreSpotlight

/// Indexes duplicate groups into macOS Spotlight so users can find duplicates
/// through system search.
///
/// All indexing is performed using the local `CSSearchableIndex` and never
/// sends data to a remote server.
public actor SpotlightIndexer {
    private let index: CSSearchableIndex

    /// Creates the indexer using the default local Spotlight index.
    public init() {
        index = CSSearchableIndex(name: "kDupe")
    }

    /// Indexes the provided duplicate groups so they appear in Spotlight results.
    ///
    /// Each group is added as a `CSSearchableItem` with the domain identifier
    /// `"com.kraftly.kdupe.duplicates"`.
    /// - Parameter groups: The duplicate groups to index.
    /// - Throws: Any error from the underlying `CSSearchableIndex`.
    public func indexGroups(_ groups: [DuplicateGroup]) async throws {
        let items = groups.map { group -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .data)
            attributes.title = "\(group.category.rawValue) Duplicates"
            attributes.contentDescription = """
            \(group.fileCount) files, \(byteCountString(group.totalSize)) total
            """
            attributes.keywords = ["kDupe", "duplicate", group.category.rawValue]

            return CSSearchableItem(
                uniqueIdentifier: group.id.uuidString,
                domainIdentifier: "com.kraftly.kdupe.duplicates",
                attributeSet: attributes
            )
        }

        try await index.indexSearchableItems(items)
    }

    /// Removes all kDupe items from the Spotlight index.
    public func clearIndex() async throws {
        try await index.deleteSearchableItems(withDomainIdentifiers: ["com.kraftly.kdupe.duplicates"])
    }

    /// Performs a Spotlight query scoped to kDupe items.
    ///
    /// Returns an array of `CSSearchableItem` matching the query string.
    /// - Parameter query: The user-facing query string.
    /// - Returns: Matching search items.
    public func search(_ query: String) async throws -> [CSSearchableItem] {
        let escaped = query.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let queryString = "domainIdentifier == \"com.kraftly.kdupe.duplicates\" && \(escaped)"

        let searchQuery = CSSearchQuery(queryString: queryString, attributes: nil)
        var results: [CSSearchableItem] = []

        return try await withCheckedThrowingContinuation { continuation in
            searchQuery.foundItemsHandler = { items in
                results.append(contentsOf: items)
            }
            searchQuery.completionHandler = { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: results)
                }
            }
            searchQuery.start()
        }
    }

    private func byteCountString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#endif
