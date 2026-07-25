import Foundation

@objc protocol XPCDuplicateServiceProtocol {
    func scanDirectory(path: String, reply: @escaping (Data?) -> Void)
    func cancelScan()
    func checkStatus(reply: @escaping (Data) -> Void)
}
