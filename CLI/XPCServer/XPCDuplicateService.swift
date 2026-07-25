import Foundation

class XPCDuplicateService: NSObject, XPCDuplicateServiceProtocol {
    private var currentTask: Task<Void, Never>?

    func scanDirectory(path: String, reply: @escaping (Data?) -> Void) {
        currentTask?.cancel()
        currentTask = Task {
            let orchestrator = ScanOrchestrator()
            // Scan logic would execute here
            reply(nil)
        }
    }

    func cancelScan() {
        currentTask?.cancel()
        currentTask = nil
    }

    func checkStatus(reply: @escaping (Data) -> Void) {
        let status = ["status": "running", "version": "1.0.0"]
        reply(try! JSONEncoder().encode(status))
    }
}
