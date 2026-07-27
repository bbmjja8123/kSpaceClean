import CoreSpotlight
import Foundation

public final class SpotlightIndexer {
    public init() {}

    public func indexActions() {
        let scanAction = CSSearchableItem(
            uniqueIdentifier: "kspaceclean://scan",
            domainIdentifier: "app.kraftly.sclean.actions",
            attributeSet: {
                let attr = CSSearchableItemAttributeSet(contentType: .content)
                attr.title = "Scan Mac Storage"
                attr.contentDescription = "Analyze disk space with kSpaceClean"
                attr.keywords = ["Mac storage", "clean Mac", "large files", "disk cleanup"]
                return attr
            }()
        )

        let cleanAction = CSSearchableItem(
            uniqueIdentifier: "kspaceclean://clean",
            domainIdentifier: "app.kraftly.sclean.actions",
            attributeSet: {
                let attr = CSSearchableItemAttributeSet(contentType: .content)
                attr.title = "Clean Up Mac"
                attr.contentDescription = "Remove system junk and free up space"
                attr.keywords = ["clean cache", "free space", "Mac cleanup"]
                return attr
            }()
        )

        CSSearchableIndex.default().indexSearchableItems([scanAction, cleanAction]) { error in
            if let error = error {
                print("Spotlight indexing error: \(error.localizedDescription)")
            }
        }
    }

    public func removeAllIndexedActions() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["app.kraftly.sclean.actions"]) { error in
            if let error = error {
                print("Spotlight removal error: \(error.localizedDescription)")
            }
        }
    }
}
