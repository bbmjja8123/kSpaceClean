import CoreData
import Foundation

public actor DuplicateRepositoryCoreData: DuplicateRepositoryProtocol {
    private let controller: PersistenceController

    public init(controller: PersistenceController = .shared) {
        self.controller = controller
    }

    public func saveScanRecord(_ record: ScanRecord) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let entity = ScanRecordEntity(context: context)
            entity.id = record.id
            entity.timestamp = record.timestamp
            entity.profileType = record.profileType.rawValue
            entity.totalFilesScanned = Int64(record.totalFilesScanned)
            entity.totalDuplicatesFound = Int64(record.totalDuplicatesFound)
            entity.totalWasteSize = record.totalWasteSize
            entity.duration = record.duration

            for group in record.groups {
                let groupEntity = DuplicateGroupEntity(context: context)
                groupEntity.id = group.id
                groupEntity.category = group.category.rawValue
                groupEntity.totalSize = group.totalSize
                groupEntity.fileCount = Int64(group.fileCount)
                groupEntity.scanRecord = entity

                for file in group.files {
                    let fileEntity = FileItemEntity(context: context)
                    fileEntity.id = file.id
                    fileEntity.filePath = file.url.path
                    fileEntity.size = file.size
                    fileEntity.modificationDate = file.modificationDate
                    fileEntity.hashValue = file.hash
                    fileEntity.group = groupEntity
                }
            }
            try context.save()
        }
    }

    public func loadScanRecords() async throws -> [ScanRecord] {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let request = ScanRecordEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            let results = try context.fetch(request)
            return results.map { self.mapToRecord($0) }
        }
    }

    public func loadScanRecord(id: UUID) async throws -> ScanRecord? {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let request = ScanRecordEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            return try context.fetch(request).first.map { self.mapToRecord($0) }
        }
    }

    public func deleteScanRecord(id: UUID) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let request = ScanRecordEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try context.fetch(request).first {
                context.delete(entity)
                try context.save()
            }
        }
    }

    public func saveCleanupAction(_ action: CleanupAction) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let entity = CleanupActionEntity(context: context)
            entity.id = action.id
            entity.filePath = action.file.url.path
            entity.fileSize = action.file.size
            entity.method = action.method.rawValue
            entity.timestamp = action.timestamp
            entity.isCompleted = action.isCompleted
            try context.save()
        }
    }

    public func loadCleanupHistory() async throws -> [CleanupRecord] {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let request = CleanupActionEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            let results = try context.fetch(request)
            let grouped = Dictionary(grouping: results) { Calendar.current.startOfDay(for: $0.timestamp) }
            return grouped.compactMap { _, entities in
                let actions = entities.map { CleanupAction(
                    id: $0.id,
                    file: FileItem(id: $0.id, url: URL(fileURLWithPath: $0.filePath),
                                   size: $0.fileSize, modificationDate: $0.timestamp, hash: nil),
                    method: CleanupMethod(rawValue: $0.method) ?? .trash,
                    timestamp: $0.timestamp,
                    isCompleted: $0.isCompleted
                )}
                let total = actions.filter(\.isCompleted).reduce(0) { $0 + $1.file.size }
                return CleanupRecord(id: UUID(), timestamp: entities.first?.timestamp ?? Date(),
                                     actions: actions, totalSpaceReclaimed: total)
            }
        }
    }

    private func mapToRecord(_ entity: ScanRecordEntity) -> ScanRecord {
        let groups = entity.groups.map { groupEntity -> DuplicateGroup in
            let files = groupEntity.files.map { fileEntity -> FileItem in
                FileItem(id: fileEntity.id, url: URL(fileURLWithPath: fileEntity.filePath),
                         size: fileEntity.size, modificationDate: fileEntity.modificationDate,
                         hash: fileEntity.hashValue)
            }
            return DuplicateGroup(
                id: groupEntity.id,
                category: DuplicateCategory(rawValue: groupEntity.category) ?? .identical,
                totalSize: groupEntity.totalSize,
                fileCount: Int(groupEntity.fileCount),
                files: Array(files)
            )
        }
        return ScanRecord(
            id: entity.id, timestamp: entity.timestamp,
            profileType: ProfileType(rawValue: entity.profileType) ?? .developer,
            totalFilesScanned: Int(entity.totalFilesScanned),
            totalDuplicatesFound: Int(entity.totalDuplicatesFound),
            totalWasteSize: entity.totalWasteSize,
            duration: entity.duration,
            groups: Array(groups)
        )
    }
}
