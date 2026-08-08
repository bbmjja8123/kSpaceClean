import Foundation

struct CLI {
    func run() {
        let args = CommandLine.arguments
        guard args.count > 1 else { printUsage(); return }

        switch args[1] {
        case "scan":       ScanCommand().execute(Array(args.dropFirst(2)))
        case "results":    ResultsCommand().execute(Array(args.dropFirst(2)))
        case "cleanup":    CleanupCommand().execute(Array(args.dropFirst(2)))
        case "watch":      WatchCommand().execute(Array(args.dropFirst(2)))
        case "history":    HistoryCommand().execute(Array(args.dropFirst(2)))
        case "web":        WebCommand().execute(Array(args.dropFirst(2)))
        case "version":    VersionCommand().execute(Array(args.dropFirst(2)))
        default:           printUsage()
        }
    }

    private func printUsage() {
        print("Usage: ksift <command> [options]")
        print("Commands: scan, results, cleanup, watch, history, web, version")
    }
}

let cli = CLI()
cli.run()
