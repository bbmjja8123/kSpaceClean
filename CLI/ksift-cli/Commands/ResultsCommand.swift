import Foundation

struct ResultsCommand {
    func execute(_ args: [String]) {
        let format = args.contains("--json") ? "json" : "text"
        let connection = NSXPCConnection(serviceName: "app.kraftly.kdupe.xpc")
        connection.remoteObjectInterface = NSXPCInterface(with: XPCDuplicateServiceProtocol.self)
        connection.resume()
        let service = connection.remoteObjectProxy as? XPCDuplicateServiceProtocol
        let semaphore = DispatchSemaphore(value: 0)
        service?.checkStatus { data in
            if let result = String(data: data, encoding: .utf8) {
                print(result)
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }
}
