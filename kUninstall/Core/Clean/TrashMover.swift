import Foundation
import AppKit

actor TrashMover {
    private let backupManager = BackupManager()
    private let historyRepo = UninstallHistoryRepository()

    static func canMoveToTrash(app: InstalledApp) -> Bool {
        !app.isProtected
    }

    func moveToTrash(app: InstalledApp, residues: [ResidueFile]) async -> Result<UninstallRecord, TrashError> {
        guard Self.canMoveToTrash(app: app) else { return .failure(.protected) }

        // Step 1: Terminate if running
        if app.isRunning {
            await terminateApp(app)
        }

        // Step 2: Backup residues
        let backupPath: URL?
        do {
            backupPath = try await backupManager.backup(residues: residues, bundleID: app.bundleID)
        } catch {
            backupPath = nil
        }

        // Step 3: Move app to trash
        do {
            try NSWorkspace.shared.recycle([app.url]) { _, _ in }
        } catch {
            return .failure(.trashFailed(error))
        }

        // Step 4: Delete residues (already backed up)
        for residue in residues where residue.confidence > 0.5 {
            try? FileManager.default.removeItem(at: residue.url)
        }

        // Step 5: Save history
        let record = UninstallRecord(
            id: UUID(),
            appName: app.displayName,
            bundleID: app.bundleID,
            appPath: app.url.path,
            appSize: app.sizeBytes,
            totalResidueSize: residues.reduce(0) { $0 + $1.sizeBytes },
            residueCount: Int32(residues.count),
            uninstalledAt: Date(),
            isRestored: false,
            backupPath: backupPath?.path ?? "",
            residues: residues
        )
        await historyRepo.save(record: record)

        return .success(record)
    }

    func restore(record: UninstallRecord) async -> Bool {
        // Step 1: Move app back from trash
        let trashURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash")
            .appendingPathComponent(URL(fileURLWithPath: record.appPath).lastPathComponent)

        if FileManager.default.fileExists(atPath: trashURL.path) {
            try? FileManager.default.moveItem(at: trashURL, to: URL(fileURLWithPath: record.appPath))
        }

        // Step 2: Restore residues
        if !record.backupPath.isEmpty {
            let backupURL = URL(fileURLWithPath: record.backupPath)
            let residues = record.residues
            try? await backupManager.restore(backupPath: backupURL, originalResidues: residues)
        }

        // Step 3: Mark restored
        await historyRepo.markRestored(id: record.id)
        await backupManager.cleanup(bundleID: record.bundleID)

        return true
    }

    private func terminateApp(_ app: InstalledApp) async {
        let runningApps = NSWorkspace.shared.runningApplications
        guard let running = runningApps.first(where: { $0.bundleIdentifier == app.bundleID }) else { return }
        running.terminate()
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if !running.isTerminated {
            running.forceTerminate()
        }
    }
}

enum TrashError: Error {
    case protected
    case trashFailed(Error)
    case restoreFailed(Error)
}

struct UninstallRecord: Identifiable, Codable {
    let id: UUID
    let appName: String
    let bundleID: String
    let appPath: String
    let appSize: Int64
    let totalResidueSize: Int64
    let residueCount: Int32
    let uninstalledAt: Date
    var isRestored: Bool
    let backupPath: String
    let residues: [ResidueFile]
}
