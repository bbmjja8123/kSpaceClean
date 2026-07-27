import Foundation

// MARK: - Filter Rules
/// Represents a single filter condition (匹配 Lemon garbage.xml 的 <filter>)
public struct FilterRule: Codable, Sendable {
    public enum Column: String, Codable, Sendable {
        case filename
        case filepath
        case filesize
        case time
        case bundleid
        case subfilecount
        case subfilepath
        case app          // "signed" / "unsigned"
        case languageKey  // "laungeuagekey" in Lemon
    }

    public enum Relation: String, Codable, Sendable {
        case `is`
        case beginsWith = "begin with"
        case endsWith = "end with"
        case contains
        case matches
        case greater
        case smaller
    }

    public enum FilterAction: String, Codable, Sendable {
        case include
        case exclude
    }

    public let id: Int
    public let column: Column
    public let relation: Relation
    public let value: String
    public let action: FilterAction

    public init(id: Int, column: Column, relation: Relation, value: String, action: FilterAction) {
        self.id = id
        self.column = column
        self.relation = relation
        self.value = value
        self.action = action
    }
}

// MARK: - Filter Expression
/// Filter 表达式，支持 AND(+) / OR(|) 组合，如 "(23+25+28)" 或 "(8+(9|10|11))"
public indirect enum FilterExpression: Codable, Sendable {
    case filterID(Int)
    case and([FilterExpression])
    case or([FilterExpression])
}

// MARK: - Action Types
public enum ScanActionType: String, Codable, Sendable, CaseIterable {
    /// 普通文件扫描
    case file
    /// 目录级扫描
    case directory
    /// 开发残留 (Xcode 等)
    case developer
    /// 无用二进制架构
    case binary
    /// 多余语言包
    case language
    /// 损坏的 plist 配置
    case brokenPlist
    /// 损坏的 Launch 注册项
    case brokenRegister
    /// 已卸载应用的残留
    case appLeftover
    /// iOS 缓存
    case iOSCache
    /// 微信聊天图片
    case wechatImage
    /// 微信文件
    case wechatFile
    /// 微信视频
    case wechatVideo
    /// 微信语音
    case wechatAudio
    /// Xcode DerivedData .app
    case derivedApp
    /// 压缩包
    case archive
    /// 邮件附件
    case mail
    /// 应用缓存
    case appCache
    /// 残留缓存
    case leftCache
    /// 残留日志
    case leftLog
    /// 软件残留
    case soft
}

// MARK: - Risk Levels (v3 UX spec §1.2)

/// 4-level risk classification for scan results
public enum RiskLevel: Int, Codable, Sendable, CaseIterable, Comparable {
    case recommended = 0   // 推荐（绿色 #34c759）— 可安全清理
    case optional = 1      // 可选（蓝色 #0a84ff）— 清理效果有限但无副作用
    case caution = 2       // 注意（橙色 #ff9500）— 清理后需重新登录/重建
    case dangerous = 3     // 危险（红色 #ff3b30）— 应用运行中/不可逆/可能丢数据

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Initialize from scan action properties
    public static func from(recommended: Bool, cautionID: Int?) -> RiskLevel {
        if let cid = cautionID, cid != 0 {
            return .caution
        }
        return recommended ? .recommended : .optional
    }

    /// Color name for SwiftUI (use system colors at call site)
    public var colorName: String {
        switch self {
        case .recommended: return "success"
        case .optional: return "brandPrimary"
        case .caution: return "warning"
        case .dangerous: return "danger"
        }
    }

    public var displayName: String {
        switch self {
        case .recommended: return "推荐"
        case .optional: return "可选"
        case .caution: return "注意"
        case .dangerous: return "危险"
        }
    }
}

/// 3-state checkbox for tree cascade
public enum CheckState: Sendable, Equatable {
    case unchecked
    case mixed        // 部分子项被选
    case checked

    /// Compute check state from selection counts
    public static func from(selected: Bool, total: Int, selectedCount: Int) -> CheckState {
        if selectedCount == 0 { return .unchecked }
        if selectedCount == total { return .checked }
        return .mixed
    }
}

/// Recommend policy controls default selection behavior
public enum RecommendPolicy: String, Codable, Sendable, CaseIterable {
    case strict                   // 仅勾「推荐」项
    case `default`                // 勾「推荐 + 可选」项
    case autoSelectCaution        // 勾「推荐 + 可选 + 注意」项

    /// Whether a given risk level should be selected by default under this policy
    public func shouldSelect(_ level: RiskLevel) -> Bool {
        switch (self, level) {
        case (_, .dangerous): return false
        case (_, .recommended): return true
        case (_, .optional): return self != .strict
        case (_, .caution): return self == .autoSelectCaution
        }
    }
}

/// Determines whether a node should be default-selected based on risk level and policy
public struct DefaultSelectionPolicy: Sendable {
    public let policy: RecommendPolicy

    public init(policy: RecommendPolicy = .default) {
        self.policy = policy
    }

    public func shouldSelect(_ riskLevel: RiskLevel) -> Bool {
        policy.shouldSelect(riskLevel)
    }

    public func shouldSelect(recommended: Bool, cautionID: Int?) -> Bool {
        let level = RiskLevel.from(recommended: recommended, cautionID: cautionID)
        return shouldSelect(level)
    }
}

// MARK: - Clean Attributes
public struct CleanAttributes: OptionSet, Codable, Sendable {
    public let rawValue: Int
    public static let truncate          = CleanAttributes(rawValue: 1 << 0)
    public static let cutBinary         = CleanAttributes(rawValue: 1 << 1)
    public static let removeLanguage    = CleanAttributes(rawValue: 1 << 2)
    public static let safariCookie      = CleanAttributes(rawValue: 1 << 3)
    public static let cleanEmptyFolder  = CleanAttributes(rawValue: 1 << 4)
    public static let cleanHiddenFile   = CleanAttributes(rawValue: 1 << 5)
    public init(rawValue: Int) { self.rawValue = rawValue }
}

// MARK: - Scan Path
public struct ScanPath: Codable, Sendable {
    public enum PathType: String, Codable, Sendable {
        /// 绝对路径 (~/ 会被展开)
        case absolute
        /// 系统临时目录 (NSTemporaryDirectory())
        case tempDir
        /// Firefox profiles 目录
        case fireFoxProfiles
        /// 根据名称搜索路径
        case searchName
        /// 根据 bundle ID 搜索路径
        case searchBundle
    }

    public let type: PathType
    public let value: String
    /// 扫描深度: 0=自身, 1=直接子项, -1=递归全部, N=N层
    public let level: Int
    /// 文件名正则过滤 (可选)
    public let filenamePattern: String?
    /// 路径过滤条件
    public let scanFilters: FilterExpression?

    public init(type: PathType, value: String, level: Int, filenamePattern: String? = nil, scanFilters: FilterExpression? = nil) {
        self.type = type
        self.value = value
        self.level = level
        self.filenamePattern = filenamePattern
        self.scanFilters = scanFilters
    }
}

// MARK: - Scan Action
public struct ScanAction: Codable, Sendable {
    public let actionID: Int?
    public let type: ScanActionType
    public let title: String
    public let paths: [ScanPath]
    /// 结果过滤条件 (atom filters)
    public let resultFilters: FilterExpression?
    /// 警告提示 ID
    public let cautionID: Int?
    public let cleanHiddenFiles: Bool
    public let cleanEmptyFolders: Bool
    public let recommended: Bool
    public let cleanAttributes: CleanAttributes

    public init(actionID: Int? = nil, type: ScanActionType, title: String, paths: [ScanPath],
                resultFilters: FilterExpression? = nil, cautionID: Int? = nil,
                cleanHiddenFiles: Bool = false, cleanEmptyFolders: Bool = true, recommended: Bool = true,
                cleanAttributes: CleanAttributes = []) {
        self.actionID = actionID
        self.type = type
        self.title = title
        self.paths = paths
        self.resultFilters = resultFilters
        self.cautionID = cautionID
        self.cleanHiddenFiles = cleanHiddenFiles
        self.cleanEmptyFolders = cleanEmptyFolders
        self.recommended = recommended
        self.cleanAttributes = cleanAttributes
    }
}

// MARK: - Scan SubCategory (Item)
public struct ScanSubCategory: Codable, Sendable {
    public let id: Int
    public let title: String
    public let tips: String?
    public let recommended: Bool
    public let actions: [ScanAction]

    public init(id: Int, title: String, tips: String? = nil, recommended: Bool = true, actions: [ScanAction]) {
        self.id = id
        self.title = title
        self.tips = tips
        self.recommended = recommended
        self.actions = actions
    }
}

// MARK: - Scan Category
public struct ScanCategory: Codable, Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let tips: String
    public let subCategories: [ScanSubCategory]

    public var categoryID: Int { id }

    public init(id: Int, title: String, tips: String, subCategories: [ScanSubCategory]) {
        self.id = id
        self.title = title
        self.tips = tips
        self.subCategories = subCategories
    }
}

// MARK: - Scan Result
/// 一次扫描操作的结果条目
public struct ScanResultEntry: Sendable {
    public let path: String
    public let size: Int64
    public let category: String  // FileCategory rawValue
    public let subCategoryID: Int
    public let actionID: Int?
    public let isTruncatable: Bool // 能否截断清空(日志)
    public let isRecommended: Bool

    public init(path: String, size: Int64, category: String, subCategoryID: Int, actionID: Int? = nil, isTruncatable: Bool = false, isRecommended: Bool = true) {
        self.path = path
        self.size = size
        self.category = category
        self.subCategoryID = subCategoryID
        self.actionID = actionID
        self.isTruncatable = isTruncatable
        self.isRecommended = isRecommended
    }
}

// MARK: - Complete Rule Set
/// 完整的内置扫描规则集（对应 Lemon garbage.xml 的 8 大分类）
public struct ScanRuleSet: Codable, Sendable {
    public let version: String
    public let filters: [Int: FilterRule]
    public let categories: [ScanCategory]

    public static let `default` = ScanRuleSet(
        version: "2026.1",
        filters: Self.defaultFilters,
        categories: Self.defaultCategories
    )
}

// MARK: - Built-in Filter Definitions
extension ScanRuleSet {
    /// 所有内置 filter 规则 (Key = filter ID)
    public static let defaultFilters: [Int: FilterRule] = {
        var f: [Int: FilterRule] = [:]

        // ── Category 1: 日志&缓存文件 ──

        // 排除系统保留缓存
        f[1] = FilterRule(id: 1, column: .filename, relation: .is, value: "com.apple.dock", action: .exclude)
        f[2] = FilterRule(id: 2, column: .filename, relation: .is, value: "com.apple.appstore", action: .exclude)
        f[3] = FilterRule(id: 3, column: .filename, relation: .is, value: "com.apple.dock.iconcache", action: .exclude)
        f[4] = FilterRule(id: 4, column: .filename, relation: .is, value: "com.apple.FontRegistry", action: .exclude)
        f[5] = FilterRule(id: 5, column: .filename, relation: .beginsWith, value: "com.apple.LaunchServices-", action: .exclude)
        f[6] = FilterRule(id: 6, column: .filename, relation: .is, value: "com.apple.Safari", action: .exclude)
        f[7] = FilterRule(id: 7, column: .filename, relation: .is, value: "com.apple.Spotlight", action: .exclude)
        f[21] = FilterRule(id: 21, column: .filename, relation: .is, value: "com.apple.IconServices", action: .exclude)
        f[26] = FilterRule(id: 26, column: .filename, relation: .is, value: "DiagnosticReports", action: .exclude)

        // 排除游戏/应用的缓存
        f[15] = FilterRule(id: 15, column: .filename, relation: .is, value: "com.rovio.mac.badpiggies", action: .exclude)
        f[16] = FilterRule(id: 16, column: .filename, relation: .is, value: "com.naturalmotion.csrracingmac", action: .exclude)
        f[17] = FilterRule(id: 17, column: .filename, relation: .is, value: "Axure-", action: .exclude)
        f[18] = FilterRule(id: 18, column: .filename, relation: .is, value: "com.glu.macos.ewarriors2", action: .exclude)
        f[19] = FilterRule(id: 19, column: .filename, relation: .is, value: "com.glu.macos.ckzombies2", action: .exclude)
        f[20] = FilterRule(id: 20, column: .filename, relation: .is, value: "com.naturalmotion.csrracingmac", action: .exclude)
        f[27] = FilterRule(id: 27, column: .filename, relation: .is, value: "com.glu.macos.deerhunt2", action: .exclude)

        // 排除浏览器缓存目录
        f[23] = FilterRule(id: 23, column: .filepath, relation: .is, value: "~/Library/Caches/Metadata/", action: .exclude)
        f[25] = FilterRule(id: 25, column: .filepath, relation: .is, value: "~/Library/Caches/Google/", action: .exclude)
        f[28] = FilterRule(id: 28, column: .filepath, relation: .is, value: "~/Library/Caches/Opera/", action: .exclude)
        f[29] = FilterRule(id: 29, column: .filepath, relation: .is, value: "~/Library/Caches/QQBrowser2/", action: .exclude)
        f[30] = FilterRule(id: 30, column: .filepath, relation: .is, value: "~/Library/Caches/Firefox/", action: .exclude)
        f[31] = FilterRule(id: 31, column: .filepath, relation: .is, value: "~/Library/Caches/com.apple.Safari/", action: .exclude)
        f[32] = FilterRule(id: 32, column: .filepath, relation: .is, value: "~/Library/Caches/Google/Chrome/Default/Cache/", action: .exclude)
        f[33] = FilterRule(id: 33, column: .filepath, relation: .beginsWith, value: "~/Library/Caches/Microsoft", action: .exclude)
        f[34] = FilterRule(id: 34, column: .filepath, relation: .beginsWith, value: "~/Library/Containers/com.microsoft.", action: .exclude)
        f[35] = FilterRule(id: 35, column: .filepath, relation: .matches, value: "/private/var/folders/.*/.*/com\\.microsoft\\..*", action: .exclude)

        // 日志文件包含规则（大于10KB + 日志模式）
        f[8] = FilterRule(id: 8, column: .filesize, relation: .greater, value: "10000", action: .include)
        f[9] = FilterRule(id: 9, column: .filename, relation: .matches, value: "^access.log*", action: .include)
        f[10] = FilterRule(id: 10, column: .filename, relation: .matches, value: "^page.log*", action: .include)
        f[11] = FilterRule(id: 11, column: .filename, relation: .matches, value: "^error.log*", action: .include)
        f[12] = FilterRule(id: 12, column: .filename, relation: .matches, value: ".+\\.out", action: .include)
        f[13] = FilterRule(id: 13, column: .filename, relation: .matches, value: ".+\\.log\\..+", action: .include)
        f[14] = FilterRule(id: 14, column: .filename, relation: .endsWith, value: "log", action: .include)

        // ── Category 2: 开发残留 ──
        f[210] = FilterRule(id: 210, column: .bundleid, relation: .beginsWith, value: "com.apple", action: .exclude)
        f[214] = FilterRule(id: 214, column: .bundleid, relation: .beginsWith, value: "com.microsoft", action: .exclude)
        f[215] = FilterRule(id: 215, column: .bundleid, relation: .beginsWith, value: "com.ittybittyapps", action: .exclude)

        // ── Category 3: 二进制 ──
        f[300] = FilterRule(id: 300, column: .app, relation: .is, value: "signed", action: .exclude)

        // ── Category 4: 语言包 ──
        f[211] = FilterRule(id: 211, column: .languageKey, relation: .is, value: "en", action: .exclude)
        f[212] = FilterRule(id: 212, column: .languageKey, relation: .beginsWith, value: "zh", action: .exclude)
        f[213] = FilterRule(id: 213, column: .bundleid, relation: .is, value: "com.apple.dt.Xcode", action: .exclude)

        // ── Category 6: iOS 缓存 ──
        f[70] = FilterRule(id: 70, column: .subfilecount, relation: .greater, value: "1", action: .include)
        f[71] = FilterRule(id: 71, column: .subfilepath, relation: .is, value: "~/Pictures/iPod Photo Cache/Photo DataBase", action: .include)

        // ── Category 7: 应用残留 ──
        f[100] = FilterRule(id: 100, column: .filename, relation: .beginsWith, value: "com.microsoft.office", action: .exclude)
        f[101] = FilterRule(id: 101, column: .filename, relation: .matches, value: ".+com\\.apple.+", action: .exclude)
        f[102] = FilterRule(id: 102, column: .filename, relation: .beginsWith, value: "loginwindow", action: .exclude)
        f[103] = FilterRule(id: 103, column: .filename, relation: .beginsWith, value: "UserEventAgent", action: .exclude)
        f[104] = FilterRule(id: 104, column: .filename, relation: .beginsWith, value: "com.hex-rays.IDA", action: .exclude)
        f[105] = FilterRule(id: 105, column: .filename, relation: .matches, value: ".+\\.[s|S]team.*", action: .exclude)
        f[36] = FilterRule(id: 36, column: .time, relation: .greater, value: "2592000", action: .include) // 30天

        // ── Category 8: 浏览器缓存 - Chrome ──
        f[240] = FilterRule(id: 240, column: .filename, relation: .beginsWith, value: "Current Tabs", action: .include)
        f[241] = FilterRule(id: 241, column: .filename, relation: .beginsWith, value: "Visited Links", action: .include)
        f[242] = FilterRule(id: 242, column: .filename, relation: .beginsWith, value: "Last Tabs", action: .include)
        f[243] = FilterRule(id: 243, column: .filename, relation: .beginsWith, value: "History", action: .include)
        f[244] = FilterRule(id: 244, column: .filename, relation: .beginsWith, value: "Archived History", action: .include)
        f[245] = FilterRule(id: 245, column: .filename, relation: .beginsWith, value: "Current Session", action: .include)
        f[246] = FilterRule(id: 246, column: .filename, relation: .beginsWith, value: "Last Session", action: .include)
        f[247] = FilterRule(id: 247, column: .filename, relation: .beginsWith, value: "Top Sites", action: .include)
        f[248] = FilterRule(id: 248, column: .filename, relation: .matches, value: "http_.*\\.localstorage", action: .include)
        f[249] = FilterRule(id: 249, column: .filename, relation: .matches, value: "http_.*\\.localstorage-journal", action: .include)
        f[261] = FilterRule(id: 261, column: .filename, relation: .matches, value: "https_.*\\.localstorage", action: .include)
        f[262] = FilterRule(id: 262, column: .filename, relation: .matches, value: "https_.*\\.localstorage-journal", action: .include)

        // ── Category 8: 浏览器缓存 - Safari ──
        f[250] = FilterRule(id: 250, column: .filename, relation: .is, value: "Downloads.plist", action: .include)
        f[251] = FilterRule(id: 251, column: .filename, relation: .is, value: "Form Values", action: .include)
        f[252] = FilterRule(id: 252, column: .filename, relation: .is, value: "LastSession.plist", action: .include)
        f[253] = FilterRule(id: 253, column: .filename, relation: .is, value: "History", action: .include)
        f[254] = FilterRule(id: 254, column: .filename, relation: .is, value: "WebpageIcons.db", action: .include)

        // ── Category 8: 浏览器缓存 - FireFox ──
        f[260] = FilterRule(id: 260, column: .filename, relation: .beginsWith, value: "cookies.sqlite", action: .include)

        // ── Time-based filters for browser cache ──
        f[37] = FilterRule(id: 37, column: .time, relation: .greater, value: "604800", action: .include)    // 7 days
        f[38] = FilterRule(id: 38, column: .time, relation: .greater, value: "86400", action: .include)     // 1 day

        // ── App leftover exclusions (Category 7) ──
        f[106] = FilterRule(id: 106, column: .filename, relation: .beginsWith, value: "com.apple.appstore", action: .exclude)
        f[107] = FilterRule(id: 107, column: .filename, relation: .beginsWith, value: "com.spotify", action: .exclude)
        f[108] = FilterRule(id: 108, column: .filename, relation: .beginsWith, value: "com.google.Chrome", action: .exclude)
        f[109] = FilterRule(id: 109, column: .filename, relation: .beginsWith, value: "com.tencent", action: .exclude)

        // ── Bundle ID filters for Category 2 (dev junk) ──
        f[216] = FilterRule(id: 216, column: .bundleid, relation: .beginsWith, value: "com.jetbrains", action: .exclude)
        f[217] = FilterRule(id: 217, column: .bundleid, relation: .beginsWith, value: "com.apple.dt", action: .exclude)

        // ── Container exclusion filters (QQ/WeChat/DingTalk/IDEA) ──
        f[50] = FilterRule(id: 50, column: .filepath, relation: .contains, value: "Containers/com.tencent", action: .exclude)
        f[51] = FilterRule(id: 51, column: .filepath, relation: .contains, value: "Containers/com.alibaba", action: .exclude)
        f[52] = FilterRule(id: 52, column: .filepath, relation: .contains, value: "Containers/com.jetbrains", action: .exclude)

        // ── Left cache app exclusion filters (for "other apps" fallback) ──
        f[72] = FilterRule(id: 72, column: .filename, relation: .beginsWith, value: "com.apple.", action: .exclude)
        f[73] = FilterRule(id: 73, column: .filename, relation: .beginsWith, value: "com.microsoft.", action: .exclude)
        f[74] = FilterRule(id: 74, column: .filename, relation: .beginsWith, value: "com.adobe.", action: .exclude)
        f[75] = FilterRule(id: 75, column: .filename, relation: .beginsWith, value: "com.google.", action: .exclude)
        f[76] = FilterRule(id: 76, column: .filename, relation: .beginsWith, value: "com.tencent.", action: .exclude)
        f[77] = FilterRule(id: 77, column: .filename, relation: .beginsWith, value: "com.alibaba.", action: .exclude)
        f[78] = FilterRule(id: 78, column: .filename, relation: .beginsWith, value: "com.netease.", action: .exclude)
        f[79] = FilterRule(id: 79, column: .filename, relation: .beginsWith, value: "com.sogou.", action: .exclude)
        f[80] = FilterRule(id: 80, column: .filename, relation: .beginsWith, value: "com.baidu.", action: .exclude)
        f[81] = FilterRule(id: 81, column: .filename, relation: .beginsWith, value: "com.qiyi.", action: .exclude)
        f[82] = FilterRule(id: 82, column: .filename, relation: .beginsWith, value: "com.xunlei.", action: .exclude)
        f[83] = FilterRule(id: 83, column: .filename, relation: .beginsWith, value: "com.spotify.", action: .exclude)
        f[84] = FilterRule(id: 84, column: .filename, relation: .beginsWith, value: "com.bohemiancoding.", action: .exclude)
        f[85] = FilterRule(id: 85, column: .filename, relation: .beginsWith, value: "net.whatsapp.", action: .exclude)

        return f
    }()
}

// MARK: - Built-in Category Definitions
extension ScanRuleSet {
    public static let defaultCategories: [ScanCategory] = {
        [
            category1_logsCache,
            category2_devJunk,
            category3_binary,
            category4_language,
            category5_brokenConfig,
            category6_iOSCache,
            category7_appLeftovers,
            category8_browserCache,
        ]
    }()

    // MARK: Category 1 — 日志&缓存文件
    private static let category1_logsCache = ScanCategory(
        id: 1, title: "日志&缓存文件", tips: "清理软件以及系统产生的日志和缓存文件。",
        subCategories: [
            ScanSubCategory(id: 10, title: "用户缓存", recommended: true, actions: [
                ScanAction(type: .file, title: "Caches 目录缓存", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Caches", level: 1,
                             scanFilters: .and([.filterID(23), .filterID(25), .filterID(28), .filterID(29),
                                                .filterID(30), .filterID(15), .filterID(16), .filterID(17),
                                                .filterID(18), .filterID(19), .filterID(20), .filterID(27),
                                                .filterID(31), .filterID(33), .filterID(34)])),
                    ScanPath(type: .absolute, value: "~/Library/Caches/Google/", level: 1,
                             scanFilters: .filterID(32)),
                ]),
                ScanAction(type: .file, title: "系统临时目录", paths: [
                    ScanPath(type: .tempDir, value: "", level: 1,
                             filenamePattern: nil,
                             scanFilters: .and([.filterID(1), .filterID(2), .filterID(3),
                                                .filterID(4), .filterID(5), .filterID(6),
                                                .filterID(21), .filterID(35)])),
                ], cleanEmptyFolders: false),
                ScanAction(type: .file, title: "沙盒缓存", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Containers/(.+)/Data/Library/Caches", level: 1,
                             scanFilters: .and([.filterID(15), .filterID(16), .filterID(17),
                                                .filterID(18), .filterID(19), .filterID(20), .filterID(27)])),
                ], cleanEmptyFolders: false),
            ]),
            ScanSubCategory(id: 11, title: "系统缓存", recommended: true, actions: [
                ScanAction(type: .file, title: "系统缓存目录", paths: [
                    ScanPath(type: .absolute, value: "/Library/Caches", level: 1,
                             scanFilters: .filterID(7)),
                ]),
            ]),
            ScanSubCategory(id: 12, title: "用户日志", recommended: true, actions: [
                ScanAction(type: .file, title: "用户日志目录", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Logs", level: 1,
                             filenamePattern: nil, scanFilters: .filterID(26)),
                ], resultFilters: .filterID(8)),
                ScanAction(type: .file, title: "诊断报告", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Logs/DiagnosticReports", level: 0),
                ]),
            ]),
            ScanSubCategory(id: 13, title: "系统日志", recommended: true, actions: [
                ScanAction(type: .file, title: "系统日志目录", paths: [
                    ScanPath(type: .absolute, value: "/Library/Logs/", level: 1,
                             scanFilters: .filterID(26)),
                ], resultFilters: .filterID(8)),
                ScanAction(type: .file, title: "系统诊断报告", paths: [
                    ScanPath(type: .absolute, value: "/Library/Logs/DiagnosticReports", level: 0),
                ]),
                ScanAction(type: .file, title: "ASL 日志", paths: [
                    ScanPath(type: .absolute, value: "/private/var/log/asl/", level: 0),
                ]),
                ScanAction(type: .file, title: "诊断消息", paths: [
                    ScanPath(type: .absolute, value: "/private/var/log/DiagnosticMessages/", level: 0),
                ]),
                ScanAction(type: .file, title: "CUPS 日志", paths: [
                    ScanPath(type: .absolute, value: "/private/var/log/cups/", level: 1),
                ], resultFilters: .and([.filterID(8), .or([.filterID(9), .filterID(10), .filterID(11)])])),
                ScanAction(type: .file, title: "系统日志文件", paths: [
                    ScanPath(type: .absolute, value: "/private/var/log/", level: 1),
                ], resultFilters: .and([.filterID(8), .or([.filterID(12), .filterID(13), .filterID(14)])])),
            ]),
        ]
    )

    // MARK: Category 2 — 开发残留垃圾
    private static let category2_devJunk = ScanCategory(
        id: 2, title: "开发残留垃圾", tips: "清理应用程序开发的时候，创建的一些支持文件。",
        subCategories: [
            ScanSubCategory(id: 50, title: "开发支持文件", recommended: true, actions: [
                ScanAction(type: .developer, title: "应用开发残留", paths: [
                    ScanPath(type: .absolute, value: "/Applications/", level: -1,
                             filenamePattern: ".+\\.app",
                             scanFilters: .and([.filterID(210), .filterID(214), .filterID(215)])),
                ]),
            ]),
        ]
    )

    // MARK: Category 3 — 无用的二进制文件
    private static let category3_binary = ScanCategory(
        id: 3, title: "无用的二进制文件", tips: "清理软件中包含的不必要的二进制。",
        subCategories: [
            ScanSubCategory(id: 30, title: "多余二进制架构", recommended: true, actions: [
                ScanAction(type: .binary, title: "不必要二进制", paths: [
                    ScanPath(type: .absolute, value: "/Applications/", level: -1,
                             filenamePattern: ".+\\.app",
                             scanFilters: .and([.filterID(300), .filterID(214)])),
                ]),
            ]),
        ]
    )

    // MARK: Category 4 — 无用的程序语言包
    private static let category4_language = ScanCategory(
        id: 4, title: "无用的程序语言包", tips: "清理应用程序里你不需要的语言包。",
        subCategories: [
            ScanSubCategory(id: 20, title: "多余语言包", recommended: true, actions: [
                ScanAction(type: .language, title: "不必要语言资源", paths: [
                    ScanPath(type: .absolute, value: "/Applications/", level: -1,
                             filenamePattern: ".+\\.app",
                             scanFilters: .and([.filterID(210), .filterID(213), .filterID(214)])),
                ], resultFilters: .and([.filterID(211), .filterID(212)])),
            ]),
        ]
    )

    // MARK: Category 5 — 损坏的配置和注册项
    private static let category5_brokenConfig = ScanCategory(
        id: 5, title: "损坏的配置和注册项", tips: "清理应用程序或服务被移除之后，产生的破损登录项连接。",
        subCategories: [
            ScanSubCategory(id: 40, title: "损坏的配置", recommended: true, actions: [
                ScanAction(type: .brokenPlist, title: "损坏的偏好设置", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Preferences", level: 1,
                             filenamePattern: ".+\\.plist"),
                ], cleanHiddenFiles: false),
            ]),
            ScanSubCategory(id: 41, title: "损坏的注册项", recommended: true, actions: [
                ScanAction(type: .brokenRegister, title: "损坏的启动项", paths: [
                    ScanPath(type: .absolute, value: "~/Library/LaunchAgents", level: 1, filenamePattern: ".+\\.plist"),
                    ScanPath(type: .absolute, value: "/Library/LaunchAgents", level: 1, filenamePattern: ".+\\.plist"),
                    ScanPath(type: .absolute, value: "~/Library/LaunchDaemons", level: 1, filenamePattern: ".+\\.plist"),
                    ScanPath(type: .absolute, value: "/Library/LaunchDaemons", level: 1, filenamePattern: ".+\\.plist"),
                ], cleanHiddenFiles: false),
            ]),
        ]
    )

    // MARK: Category 6 — iOS 缓存
    private static let category6_iOSCache = ScanCategory(
        id: 6, title: "iOS升级软件&照片缓存", tips: "清理 iOS 设备同步到电脑上面的数据缓存。",
        subCategories: [
            ScanSubCategory(id: 60, title: "iOS 升级软件", recommended: true, actions: [
                ScanAction(type: .iOSCache, title: "iOS 固件文件", paths: [
                    ScanPath(type: .absolute, value: "~/Library/iTunes/", level: -1, filenamePattern: ".+\\.ipsw"),
                ]),
            ]),
            ScanSubCategory(id: 61, title: "iOS 照片缓存", recommended: true, actions: [
                ScanAction(type: .directory, title: "照片缓存", paths: [
                    ScanPath(type: .absolute, value: "~/Pictures/iPod Photo Cache/", level: 1,
                             scanFilters: .and([.filterID(70), .filterID(71)])),
                ]),
            ]),
        ]
    )

    // MARK: Category 7 — 应用程序残留
    private static let category7_appLeftovers = ScanCategory(
        id: 7, title: "应用程序残留", tips: "清理已删除软件的残留文件。",
        subCategories: [
            ScanSubCategory(id: 70, title: "应用残留文件", recommended: true, actions: [
                ScanAction(type: .appLeftover, title: "残留配置与支持文件", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Preferences", level: 1,
                             filenamePattern: ".+\\.plist",
                             scanFilters: .and([.filterID(100), .filterID(101), .filterID(102),
                                                .filterID(103), .filterID(104), .filterID(105),
                                                .filterID(36)])),
                    ScanPath(type: .searchName, value: "/Library/Application Support/", level: 1),
                    ScanPath(type: .searchBundle, value: "/Library/Application Support/", level: 1),
                    ScanPath(type: .searchName, value: "~/Library/Application Support/", level: 1),
                    ScanPath(type: .searchBundle, value: "~/Library/Application Support/", level: 1),
                    ScanPath(type: .searchBundle, value: "/Library/Caches", level: 1),
                    ScanPath(type: .searchBundle, value: "~/Library/Caches", level: 1),
                    ScanPath(type: .searchBundle, value: "/Library/Logs", level: 1),
                    ScanPath(type: .searchBundle, value: "~/Library/Logs", level: 1),
                ], cleanEmptyFolders: true),
            ]),
        ]
    )

    // MARK: Category 8 — 浏览器缓存
    private static let category8_browserCache = ScanCategory(
        id: 8, title: "浏览器缓存", tips: "清理 Chrome、Opera、Safari、Firefox 和 QQ 浏览器产生的缓存文件。",
        subCategories: [
            // Safari
            ScanSubCategory(id: 81, title: "Safari", recommended: true, actions: [
                ScanAction(type: .file, title: "浏览器缓存", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Caches/com.apple.Safari/", level: 1),
                    ScanPath(type: .absolute, value: "~/Library/Caches/Metadata/Safari/", level: 1),
                    ScanPath(type: .absolute, value: "~/Library/Safari/WebpageIcons.db", level: 0),
                ], cautionID: 1011),
                ScanAction(type: .file, title: "浏览器历史记录", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Safari/History.plist", level: 0),
                    ScanPath(type: .absolute, value: "~/Library/Safari/HistoryIndex.sk", level: 0),
                ], cautionID: 1011, recommended: false),
                ScanAction(type: .file, title: "浏览器下载记录", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Safari/Downloads.plist", level: 0),
                ], cautionID: 1011),
                ScanAction(type: .file, title: "浏览器 Cookies", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Safari/LocalStorage/", level: 0),
                ], cautionID: 1011, recommended: false),
            ]),
            // Chrome
            ScanSubCategory(id: 80, title: "Chrome", recommended: true, actions: [
                ScanAction(type: .file, title: "浏览器缓存", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Caches/Google/Chrome/Default/Cache/", level: 0),
                ], cautionID: 1012),
                ScanAction(type: .file, title: "浏览器历史记录", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Application Support/Google/Chrome/Default/", level: 1,
                             scanFilters: .or([.filterID(240), .filterID(241), .filterID(242),
                                               .filterID(243), .filterID(244), .filterID(247)])),
                ], cautionID: 1012, recommended: false),
                ScanAction(type: .file, title: "浏览器会话", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Application Support/Google/Chrome/Default/", level: 1,
                             scanFilters: .or([.filterID(245), .filterID(246)])),
                ], cautionID: 1012),
                ScanAction(type: .file, title: "浏览器 Cookies", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Application Support/Google/Chrome/Default/Local Storage/", level: 1,
                             scanFilters: .or([.filterID(248), .filterID(249), .filterID(261), .filterID(262)])),
                    ScanPath(type: .absolute, value: "~/Library/Application Support/Google/Chrome/Default", level: 1,
                             filenamePattern: "Cookies.*"),
                ], cautionID: 1012, recommended: false),
                ScanAction(type: .file, title: "保存的密码", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Application Support/Google/Chrome/Default", level: 1,
                             filenamePattern: "Login Data.*"),
                ], cautionID: 1012, recommended: false),
            ]),
            // QQBrowser
            ScanSubCategory(id: 84, title: "QQ浏览器", recommended: true, actions: [
                ScanAction(type: .file, title: "浏览器缓存", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Caches/QQBrowser2/Default/Cache/", level: 0),
                ], cautionID: 1014),
                ScanAction(type: .file, title: "浏览器历史记录", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Application Support/QQBrowser2/Default/", level: 1,
                             scanFilters: .or([.filterID(240), .filterID(241), .filterID(242),
                                               .filterID(243), .filterID(244), .filterID(247)])),
                ], cautionID: 1014, recommended: false),
                ScanAction(type: .file, title: "浏览器会话", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Application Support/QQBrowser2/Default/", level: 1,
                             scanFilters: .or([.filterID(245), .filterID(246)])),
                ], cautionID: 1014),
                ScanAction(type: .file, title: "浏览器 Cookies", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Application Support/QQBrowser2/Default/Local Storage/", level: 1),
                    ScanPath(type: .absolute, value: "~/Library/Application Support/QQBrowser2/Default/", level: 1,
                             filenamePattern: "Cookies.*"),
                ], cautionID: 1014, recommended: false),
                ScanAction(type: .file, title: "保存的密码", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Application Support/QQBrowser2/Default/", level: 1,
                             filenamePattern: "Login Data.*"),
                ], cautionID: 1014, recommended: false),
            ]),
            // Opera
            ScanSubCategory(id: 82, title: "Opera", recommended: true, actions: [
                ScanAction(type: .file, title: "浏览器缓存", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Caches/Opera/", level: 0),
                    ScanPath(type: .absolute, value: "~/Library/Application Support/com.operasoftware.Opera/GPUCache", level: 0),
                    ScanPath(type: .absolute, value: "~/Library/Caches/com.operasoftware.Opera", level: 0),
                ], cautionID: 1015),
                ScanAction(type: .file, title: "应用程序缓存", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Application Support/Opera/application_cache", level: 0),
                ], cautionID: 1015, recommended: false),
                ScanAction(type: .file, title: "浏览器会话", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Opera/sessions/", level: 1),
                    ScanPath(type: .absolute, value: "~/Library/Application Support/com.operasoftware.Opera/", level: 1,
                             filenamePattern: "session.db.*"),
                ], cautionID: 1015),
                ScanAction(type: .file, title: "浏览器历史记录", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Application Support/com.operasoftware.Opera/", level: 1,
                             filenamePattern: "History.*"),
                ], cautionID: 1015, recommended: false),
                ScanAction(type: .file, title: "浏览器 Cookies", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Application Support/com.operasoftware.Opera/", level: 1,
                             filenamePattern: "Cookies.*"),
                ], cautionID: 1015, recommended: false),
                ScanAction(type: .file, title: "保存的密码", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Application Support/com.operasoftware.Opera/", level: 1,
                             filenamePattern: "Login Data.*"),
                ], cautionID: 1015, recommended: false),
            ]),
            // FireFox
            ScanSubCategory(id: 83, title: "FireFox", recommended: true, actions: [
                ScanAction(type: .file, title: "浏览器缓存", paths: [
                    ScanPath(type: .absolute, value: "~/Library/Caches/Firefox/", level: 0),
                ], cautionID: 1013),
                ScanAction(type: .file, title: "浏览器下载记录", paths: [
                    ScanPath(type: .fireFoxProfiles, value: "FireFoxProfiles", level: 1, filenamePattern: "downloads\\.sqlite"),
                ], cautionID: 1013, recommended: false),
                ScanAction(type: .file, title: "浏览器会话", paths: [
                    ScanPath(type: .fireFoxProfiles, value: "FireFoxProfiles", level: 1, filenamePattern: "sessionstore\\..*"),
                ], cautionID: 1013),
                ScanAction(type: .file, title: "浏览器 Cookies", paths: [
                    ScanPath(type: .fireFoxProfiles, value: "FireFoxProfiles", level: 1, filenamePattern: "cookies\\.sqlite"),
                ], cautionID: 1013, recommended: false),
                ScanAction(type: .file, title: "页面配置", paths: [
                    ScanPath(type: .fireFoxProfiles, value: "FireFoxProfiles", level: 1, filenamePattern: "content-prefs\\.sqlite"),
                ], cautionID: 1013, recommended: true),
                ScanAction(type: .file, title: "表单信息", paths: [
                    ScanPath(type: .fireFoxProfiles, value: "FireFoxProfiles", level: 1, filenamePattern: "formhistory\\.sqlite"),
                ], cautionID: 1013, recommended: false),
                ScanAction(type: .file, title: "保存的密码", paths: [
                    ScanPath(type: .fireFoxProfiles, value: "FireFoxProfiles", level: 1, filenamePattern: "signons\\.sqlite"),
                ], cautionID: 1013, recommended: false),
            ]),
        ]
    )
}
