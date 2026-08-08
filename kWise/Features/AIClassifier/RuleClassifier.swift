import Foundation
import DesignSystem

public struct RuleClassifier: Sendable {
    private let imageExtensions: Set<String> = ["jpg","jpeg","png","gif","bmp","tiff","webp","heic","heif","raw","cr2","nef","arw"]
    private let videoExtensions: Set<String> = ["mp4","mov","avi","mkv","wmv","flv","webm","m4v","3gp"]
    private let documentExtensions: Set<String> = ["pdf","doc","docx","xls","xlsx","ppt","pptx","txt","rtf","md","csv","json","xml","html"]
    private let audioExtensions: Set<String> = ["mp3","aac","wav","flac","ogg","wma","m4a","aiff"]
    private let cacheExtensions: Set<String> = ["cache","tmp","temp","log","swp","ds_store"]
    private let devExtensions: Set<String> = ["swift","kt","java","py","js","ts","go","rs","c","cpp","h","m","mm","plist","entitlements"]

    public init() {}

    public func classify(_ url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        if documentExtensions.contains(ext) { return .document }
        if audioExtensions.contains(ext) { return .audio }
        if cacheExtensions.contains(ext) { return .cache }
        if devExtensions.contains(ext) { return .dev }
        return .other
    }

    public func isSystemCache(_ url: URL) -> Bool {
        url.path.contains("/Caches/") || url.path.contains("/Cache/")
    }
}
