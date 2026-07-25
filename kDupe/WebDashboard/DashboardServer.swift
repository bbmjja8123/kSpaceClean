import Swifter
import Foundation

actor DashboardServer {
    private let server = HttpServer()
    private let port: UInt16 = 7711
    private var isRunning = false

    func start() throws {
        guard !isRunning else { return }
        setupRoutes()
        try server.start(port, forceIPv4: true, priority: .default)
        isRunning = true
    }

    func stop() {
        server.stop()
        isRunning = false
    }

    private func setupRoutes() {
        server["/api/status"] = { _ in
            .ok(.json(["status": "running" as AnyObject]))
        }

        server["/api/results"] = { _ in
            .ok(.json(["results": []] as AnyObject))
        }

        server["/api/scan"] = { request in
            guard request.headers["x-kdupe-token"] == self.token else {
                return .unauthorized
            }
            Task { await self.triggerScan() }
            return .accepted
        }

        server["/"] = { _ in
            .ok(.html(self.dashboardHTML))
        }

        server["/dashboard.js"] = { _ in
            .ok(.js(self.dashboardJS))
        }

        server["/dashboard.css"] = { _ in
            .ok(.css(self.dashboardCSS))
        }
    }

    private var token: String {
        UserDefaults.standard.string(forKey: "dashboardToken")
            ?? UUID().uuidString
    }

    private func triggerScan() async {
        // Would delegate to ScanOrchestrator
    }

    private var dashboardHTML: String { "" /* placeholder */ }
    private var dashboardJS: String { "" /* placeholder */ }
    private var dashboardCSS: String { "" /* placeholder */ }
}
