import XCTest
import CoreData
@testable import kSpaceClean

/// Creates an in-memory Core Data context for testing
@MainActor
func createTestContext() -> NSManagedObjectContext {
    let stack = CoreDataStack.createTestInstance()
    return stack.viewContext
}

/// Creates a test FileEntry for verification
func createTestFileEntry(context: NSManagedObjectContext,
                         path: String = "/test/file.txt",
                         size: Int64 = 1024,
                         category: String = "document") -> FileEntry {
    let entry = FileEntry(context: context)
    entry.id = UUID()
    entry.path = path
    entry.size = size
    entry.category = category
    entry.confidence = 0.95
    return entry
}
