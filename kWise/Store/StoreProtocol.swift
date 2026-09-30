import Foundation

public protocol StoreProtocol: AnyObject {
    /// `true` once the user owns the non-consumable buyout
    /// (`app.kraftly.klaris.buyout`). There is no subscription and no
    /// free trial — the free tier is the unpurchased state.
    var hasPurchased: Bool { get }
    func checkSubscription() async
    func purchase() async
    func restorePurchases() async
}
