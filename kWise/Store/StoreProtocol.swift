import Foundation

public protocol StoreProtocol: AnyObject {
    var isSubscribed: Bool { get }
    var isEligibleForTrial: Bool { get }
    func checkSubscription() async
    func purchase() async
    func restorePurchases() async
}
