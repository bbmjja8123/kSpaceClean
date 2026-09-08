// kSift/App/CleanupStack.swift
//
// App-side factory for the DetectionCore vault/scan stack. The package no
// longer ships Core Data default arguments, so the app injects its own
// repositories here — one place, so UI/intents never wire the stack by hand.
import Foundation
import DetectionCore

enum CleanupStack {
    /// Vault rooted in kSift's sandbox container Application Support dir.
    static func makeVaultManager() -> VaultManager {
        VaultManager(repository: VaultRepositoryCoreData())
    }

    static func makeCleanupManager() -> CleanupManager {
        CleanupManager(vault: makeVaultManager())
    }

    static func makeVaultCleaner() -> VaultCleaner {
        VaultCleaner(vault: makeVaultManager())
    }

    static func makeScanOrchestrator(incrementalIndex: (any IncrementalIndexProtocol)? = nil) -> ScanOrchestrator {
        ScanOrchestrator(repository: DuplicateRepositoryCoreData(), incrementalIndex: incrementalIndex)
    }
}
