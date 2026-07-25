import Foundation

struct WatchCommand {
    func execute(_ args: [String]) {
        let interval: TimeInterval = args.contains("--interval")
            ? (Double(args[args.firstIndex(of: "--interval")! + 1]) ?? 60) : 60

        print("Watching for duplicates every \(Int(interval))s...")
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            print("[\(Date().ISO8601Format())] Checking...")
        }
        RunLoop.main.run()
    }
}
