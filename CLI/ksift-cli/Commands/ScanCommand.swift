import Foundation

struct ScanCommand {
    func execute(_ args: [String]) {
        var paths: [String] = []
        var mode = "standard"
        var outputFormat = "text"
        var argIterator = args.makeIterator()
        while let arg = argIterator.next() {
            switch arg {
            case "--mode": mode = argIterator.next() ?? "standard"
            case "--json": outputFormat = "json"
            case "--csv":  outputFormat = "csv"
            default:       paths.append(arg)
            }
        }
        if paths.isEmpty { paths = [FileManager.default.currentDirectoryPath] }

        let connection = NSXPCConnection(serviceName: "app.kraftly.kdupe.xpc")
        connection.remoteObjectInterface = NSXPCInterface(with: XPCDuplicateServiceProtocol.self)
        connection.resume()

        let service = connection.remoteObjectProxy as? XPCDuplicateServiceProtocol
        let semaphore = DispatchSemaphore(value: 0)

        service?.scanDirectory(path: paths.first ?? "") { data in
            if let data = data, let result = String(data: data, encoding: .utf8) {
                print(result)
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }
}
