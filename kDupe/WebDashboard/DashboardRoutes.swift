import Swifter
import Foundation

struct DashboardRoutes {
    func statusEndpoint() -> ((HttpRequest) -> HttpResponse) {
        { _ in .ok(.json(["status": "running" as AnyObject])) }
    }

    func resultsEndpoint() -> ((HttpRequest) -> HttpResponse) {
        { _ in .ok(.json(["results": []] as AnyObject)) }
    }
}
