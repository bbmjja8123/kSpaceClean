import Foundation

struct WebCommand {
    func execute(_ args: [String]) {
        guard let url = URL(string: "http://localhost:7711/dashboard") else { return }
        NSWorkspace.shared.open(url)
        print("Opening dashboard...")
        exit(0)
    }
}
