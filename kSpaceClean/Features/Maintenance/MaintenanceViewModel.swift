import Foundation

/// View model that orchestrates the execution of maintenance scripts.
///
/// This model is bound to `@MainActor` because all published properties
/// are consumed by SwiftUI views and must be updated on the main thread.
@MainActor
public final class MaintenanceViewModel: ObservableObject, Sendable {
    /// The identifier of the script currently being executed, if any.
    @Published public var runningScript: MaintenanceScript.ID?

    /// Results keyed by script identifier. A present value indicates the
    /// script has completed (either successfully or with an error).
    @Published public var results: [MaintenanceScript.ID: String] = [:]

    public init() {}

    /// Executes the given maintenance script and stores its result.
    ///
    /// - Parameter script: The script to execute.
    public func execute(_ script: MaintenanceScript) async {
        runningScript = script.id
        defer { runningScript = nil }

        do {
            let result = try await script.execute()
            results[script.id] = result
        } catch {
            results[script.id] = "失败: \(error.localizedDescription)"
        }
    }

    /// Whether any script is currently running.
    public var isRunning: Bool {
        runningScript != nil
    }

    /// Removes the result for the given script identifier.
    ///
    /// - Parameter id: The script identifier whose result should be cleared.
    public func clearResult(for id: MaintenanceScript.ID) {
        results.removeValue(forKey: id)
    }
}
