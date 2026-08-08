import Foundation
import AppKit

// MARK: - App-Specific Scan Rule Types

/// An app-specific scan rule (matching Lemon's garbage1.xml entries)
public struct AppScanRule: Sendable {
    public let appName: String
    public let bundleID: String
    public let isSandbox: Bool
    public let isMultiUser: Bool
    public let categoryID: Int
    public let subCategoryID: Int
    public let actions: [AppScanAction]

    public init(appName: String, bundleID: String, isSandbox: Bool, isMultiUser: Bool,
                categoryID: Int, subCategoryID: Int, actions: [AppScanAction]) {
        self.appName = appName
        self.bundleID = bundleID
        self.isSandbox = isSandbox
        self.isMultiUser = isMultiUser
        self.categoryID = categoryID
        self.subCategoryID = subCategoryID
        self.actions = actions
    }
}

public struct AppScanAction: Sendable {
    public let actionID: Int
    public let title: String
    public let paths: [String]
    public let level: Int
    public let recommended: Bool
    public let cautionID: Int?
    public let requireTimeFilter: Bool

    public init(actionID: Int, title: String, paths: [String], level: Int = 0,
                recommended: Bool = true, cautionID: Int? = nil, requireTimeFilter: Bool = false) {
        self.actionID = actionID
        self.title = title
        self.paths = paths
        self.level = level
        self.recommended = recommended
        self.cautionID = cautionID
        self.requireTimeFilter = requireTimeFilter
    }
}

// MARK: - Sandbox Path Resolver

public struct SandboxResolver: Sendable {
    /// Resolve sandboxed app path: ~/Library/Containers/<bundleID>/Data/Library/<subpath>
    public static func containerURL(bundleID: String, subpath: String) -> String {
        "~/Library/Containers/\(bundleID)/Data/Library/\(subpath)"
    }

    /// Resolve non-sandboxed app support path
    public static func appSupportPath(appName: String) -> String {
        "~/Library/Application Support/\(appName)/"
    }

    /// Resolve non-sandboxed cache path
    public static func cachePath(appName: String) -> String {
        "~/Library/Caches/\(appName)/"
    }

    /// Resolve preferences path
    public static func preferencesPath(bundleID: String) -> String {
        "~/Library/Preferences/\(bundleID).plist"
    }
}

// MARK: - All 30 App Scan Rules

extension AppScanRule {
    /// All 30 app-specific scan rules
    public static let allApps: [AppScanRule] = [
        wechat, qq, tim, dingtalk, whatsapp, wework,
        sogouInput, baiduInput, googleInput, iflytekInput,
        neteaseMusic, qqMusic, xiamiMusic, kugouMusic, kwMusic, spotify,
        iQIYI, youku, tencentVideo, bilibili, kuaibo, baiduPan, thunder,
        sohuVideo, baofeng, pptv, mkPlayer,
        xcode, sketch, cctalk,
        chrome, firefox, slack, zoom, teams, docker, vscode, homebrew,
        discord, telegram, steam, adobeCreativeCloud, jetbrains,
    ]

    /// Only apps currently installed on this system
    public static func installedApps() -> [AppScanRule] {
        allApps.filter { $0.isInstalled }
    }

    // MARK: - 聊天通讯 (5 apps)

    private static let wechat = AppScanRule(
        appName: "微信", bundleID: "com.tencent.xinWeChat", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 14,
        actions: [
            AppScanAction(actionID: 1001, title: "微信缓存文件",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.xinWeChat",
                                     subpath: "Caches/com.tencent.xinWeChat/")],
                          level: -1, recommended: true, cautionID: nil),
            AppScanAction(actionID: 1002, title: "微信日志",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.xinWeChat",
                                     subpath: "Logs/com.tencent.xinWeChat/")],
                          level: -1, recommended: true, cautionID: nil),
            AppScanAction(actionID: 1003, title: "微信接收文件(大文件)",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.xinWeChat",
                                     subpath: "Data/com.tencent.xinWeChat/")],
                          level: 1, recommended: false, cautionID: 2001, requireTimeFilter: true),
            AppScanAction(actionID: 1004, title: "微信应用缓存",
                          paths: [
                              SandboxResolver.containerURL(bundleID: "com.tencent.xinWeChat", subpath: "Caches/fsCachedData/"),
                              SandboxResolver.containerURL(bundleID: "com.tencent.xinWeChat", subpath: "Caches/PinYinCache/"),
                              "~/Library/Containers/com.tencent.xinWeChat/Data/tmp/",
                          ],
                          level: -1, recommended: true),
            AppScanAction(actionID: 1005, title: "微信头像缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.xinWeChat",
                                     subpath: "Data/com.tencent.xinWeChat/")],
                          level: 1, recommended: true),
            AppScanAction(actionID: 1006, title: "微信聊天图片",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.xinWeChat",
                                     subpath: "Data/com.tencent.xinWeChat/")],
                          level: -1, recommended: false, cautionID: 2001),
            AppScanAction(actionID: 1007, title: "微信聊天视频",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.xinWeChat",
                                     subpath: "Data/com.tencent.xinWeChat/")],
                          level: -1, recommended: false, cautionID: 2001),
            AppScanAction(actionID: 1008, title: "微信语音消息",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.xinWeChat",
                                     subpath: "Data/com.tencent.xinWeChat/")],
                          level: -1, recommended: false, cautionID: 2001),
        ]
    )

    private static let qq = AppScanRule(
        appName: "QQ", bundleID: "com.tencent.qqmac", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 14,
        actions: [
            AppScanAction(actionID: 1010, title: "QQ 缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.qqmac",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 1011, title: "QQ 日志",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.qqmac",
                                     subpath: "Logs/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 1012, title: "QQ 数据库(大文件)",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.qqmac",
                                     subpath: "Data/")],
                          level: 1, recommended: false, cautionID: 2002, requireTimeFilter: true),
            AppScanAction(actionID: 1013, title: "QQ 应用缓存",
                          paths: [
                              SandboxResolver.containerURL(bundleID: "com.tencent.qqmac", subpath: "Caches/fsCachedData/"),
                              "~/Library/Containers/com.tencent.qqmac/Data/tmp/",
                          ],
                          level: -1, recommended: true),
            AppScanAction(actionID: 1014, title: "QQINI 日志",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.qqmac",
                                     subpath: "Logs/")],
                          level: -1, recommended: false),
            AppScanAction(actionID: 1015, title: "QQ 图片缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.qqmac",
                                     subpath: "Data/")],
                          level: 1, recommended: false, cautionID: 2002, requireTimeFilter: true),
            AppScanAction(actionID: 1016, title: "QQ 接收文件",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.qqmac",
                                     subpath: "Data/")],
                          level: 1, recommended: false, cautionID: 2002, requireTimeFilter: true),
            AppScanAction(actionID: 1017, title: "QQ 头像/表情",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.qqmac",
                                     subpath: "Data/")],
                          level: 1, recommended: false, cautionID: 2002, requireTimeFilter: true),
        ]
    )

    private static let tim = AppScanRule(
        appName: "TIM", bundleID: "com.tencent.tim", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 14,
        actions: [
            AppScanAction(actionID: 1020, title: "TIM 缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.tim",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 1021, title: "TIM 日志",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.tim",
                                     subpath: "Logs/")],
                          level: -1, recommended: true),
        ]
    )

    private static let dingtalk = AppScanRule(
        appName: "钉钉", bundleID: "com.alibaba.dingtalk,5ZSL2CJU2T.com.dingtalk.mac", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 14,
        actions: [
            AppScanAction(actionID: 1030, title: "钉钉缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.alibaba.dingtalk",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 1031, title: "钉钉日志",
                          paths: [SandboxResolver.containerURL(bundleID: "com.alibaba.dingtalk",
                                     subpath: "Logs/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 1032, title: "钉钉下载(大文件)",
                          paths: [SandboxResolver.containerURL(bundleID: "com.alibaba.dingtalk",
                                     subpath: "Data/")],
                          level: 1, recommended: false, cautionID: 2008, requireTimeFilter: true),
        ]
    )

    private static let whatsapp = AppScanRule(
        appName: "WhatsApp", bundleID: "net.whatsapp.WhatsApp", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 14,
        actions: [
            AppScanAction(actionID: 1040, title: "WhatsApp 缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "net.whatsapp.WhatsApp",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
        ]
    )

    // MARK: - 输入法 (3 apps)

    private static let sogouInput = AppScanRule(
        appName: "搜狗输入法", bundleID: "com.sogou.input.sogou", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 15,
        actions: [
            AppScanAction(actionID: 1050, title: "搜狗输入法缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.sogou.input.sogou",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
        ]
    )

    private static let baiduInput = AppScanRule(
        appName: "百度输入法", bundleID: "com.baidu.inputmethod", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 15,
        actions: [
            AppScanAction(actionID: 1060, title: "百度输入法缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.baidu.inputmethod",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
        ]
    )

    private static let googleInput = AppScanRule(
        appName: "Google输入法", bundleID: "com.google.inputmethod", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 15,
        actions: [
            AppScanAction(actionID: 1070, title: "Google输入法缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.google.inputmethod",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
        ]
    )

    // MARK: - 音乐 (5 apps)

    private static let neteaseMusic = AppScanRule(
        appName: "网易云音乐", bundleID: "com.netease.163music", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 16,
        actions: [
            AppScanAction(actionID: 1080, title: "网易云音乐缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.netease.163music",
                                     subpath: "Caches/com.netease.163music/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 1081, title: "网易云音乐下载(大文件)",
                          paths: [SandboxResolver.containerURL(bundleID: "com.netease.163music",
                                     subpath: "Data/com.netease.163music/")],
                          level: 1, recommended: false, cautionID: 2003, requireTimeFilter: true),
        ]
    )

    private static let qqMusic = AppScanRule(
        appName: "QQ音乐", bundleID: "com.tencent.QQMusic", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 16,
        actions: [
            AppScanAction(actionID: 1090, title: "QQ音乐缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.QQMusic",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
        ]
    )

    private static let xiamiMusic = AppScanRule(
        appName: "虾米音乐", bundleID: "com.xiami.XiamiMusic", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 16,
        actions: [
            AppScanAction(actionID: 1100, title: "虾米音乐缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.xiami.XiamiMusic",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
        ]
    )

    private static let kugouMusic = AppScanRule(
        appName: "酷狗音乐", bundleID: "com.kugou.music", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 16,
        actions: [
            AppScanAction(actionID: 1110, title: "酷狗音乐缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.kugou.music",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 1111, title: "酷狗音乐日志",
                          paths: [SandboxResolver.containerURL(bundleID: "com.kugou.music",
                                     subpath: "Logs/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 1112, title: "酷狗音乐歌词",
                          paths: [SandboxResolver.containerURL(bundleID: "com.kugou.music",
                                     subpath: "Data/")],
                          level: 1, recommended: false, requireTimeFilter: true),
            AppScanAction(actionID: 1113, title: "酷狗音乐皮肤",
                          paths: [SandboxResolver.containerURL(bundleID: "com.kugou.music",
                                     subpath: "Data/")],
                          level: 1, recommended: false, requireTimeFilter: true),
            AppScanAction(actionID: 1114, title: "酷狗音乐下载(大文件)",
                          paths: [SandboxResolver.containerURL(bundleID: "com.kugou.music",
                                     subpath: "Data/")],
                          level: 1, recommended: false, cautionID: 2007, requireTimeFilter: true),
            AppScanAction(actionID: 1115, title: "酷狗音乐应用缓存",
                          paths: [
                              SandboxResolver.containerURL(bundleID: "com.kugou.music", subpath: "Caches/fsCachedData/"),
                              "~/Library/Containers/com.kugou.music/Data/tmp/",
                          ],
                          level: -1, recommended: true),
        ]
    )

    private static let spotify = AppScanRule(
        appName: "Spotify", bundleID: "com.spotify.client", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 16,
        actions: [
            AppScanAction(actionID: 1120, title: "Spotify 缓存",
                          paths: ["~/Library/Caches/com.spotify.client/",
                                  "~/Library/Application Support/Spotify/PersistentCache/"],
                          level: -1, recommended: true),
        ]
    )

    // MARK: - 视频 (7 apps)

    private static let iQIYI = AppScanRule(
        appName: "爱奇艺", bundleID: "com.qiyi.video", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 17,
        actions: [
            AppScanAction(actionID: 1130, title: "爱奇艺缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.qiyi.video",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
        ]
    )

    private static let youku = AppScanRule(
        appName: "优酷", bundleID: "com.youku.mac", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 17,
        actions: [
            AppScanAction(actionID: 1140, title: "优酷缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.youku.mac",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
        ]
    )

    private static let tencentVideo = AppScanRule(
        appName: "腾讯视频", bundleID: "com.tencent.video", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 17,
        actions: [
            AppScanAction(actionID: 1150, title: "腾讯视频缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.video",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
        ]
    )

    private static let bilibili = AppScanRule(
        appName: "Bilibili", bundleID: "com.bilibili.mac", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 17,
        actions: [
            AppScanAction(actionID: 1160, title: "Bilibili 缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.bilibili.mac",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
        ]
    )

    private static let kuaibo = AppScanRule(
        appName: "快播", bundleID: "com.kuaibo.mac", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 17,
        actions: [
            AppScanAction(actionID: 1170, title: "快播缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.kuaibo.mac",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
        ]
    )

    private static let baiduPan = AppScanRule(
        appName: "百度网盘", bundleID: "com.baidu.netdisk", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 17,
        actions: [
            AppScanAction(actionID: 1180, title: "百度网盘缓存",
                          paths: ["~/Library/Caches/com.baidu.netdisk/",
                                  "~/Library/Application Support/com.baidu.netdisk/"],
                          level: -1, recommended: true),
        ]
    )

    private static let thunder = AppScanRule(
        appName: "迅雷", bundleID: "com.xunlei.Thunder", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 17,
        actions: [
            AppScanAction(actionID: 1190, title: "迅雷缓存",
                          paths: ["~/Library/Caches/com.xunlei.Thunder/"],
                          level: -1, recommended: true),
        ]
    )

    // MARK: - 开发工具 (2 apps)

    private static let xcode = AppScanRule(
        appName: "Xcode", bundleID: "com.apple.dt.Xcode", isSandbox: false, isMultiUser: false,
        categoryID: 2, subCategoryID: 51,
        actions: [
            AppScanAction(actionID: 1200, title: "DerivedData",
                          paths: ["~/Library/Developer/Xcode/DerivedData/"],
                          level: -1, recommended: true, cautionID: 0),
            AppScanAction(actionID: 1201, title: "iOS DeviceSupport",
                          paths: ["~/Library/Developer/Xcode/iOS DeviceSupport/"],
                          level: -1, recommended: true, cautionID: 0),
            AppScanAction(actionID: 1202, title: "CoreSimulator Caches",
                          paths: ["~/Library/Developer/CoreSimulator/Caches/"],
                          level: -1, recommended: true, cautionID: 0),
            AppScanAction(actionID: 1203, title: "Archives",
                          paths: ["~/Library/Developer/Xcode/Archives/"],
                          level: -1, recommended: false, cautionID: 2004),
            AppScanAction(actionID: 1204, title: "模拟器(大文件)",
                          paths: ["~/Library/Developer/CoreSimulator/Devices/"],
                          level: 1, recommended: false, cautionID: 2005, requireTimeFilter: true),
            AppScanAction(actionID: 1205, title: "Previews 缓存",
                          paths: ["~/Library/Developer/Xcode/UserData/Previews/"],
                          level: -1, recommended: true),
        ]
    )

    private static let sketch = AppScanRule(
        appName: "Sketch", bundleID: "com.bohemiancoding.sketch3", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 18,
        actions: [
            AppScanAction(actionID: 1210, title: "Sketch 缓存",
                          paths: ["~/Library/Caches/com.bohemiancoding.sketch3/"],
                          level: -1, recommended: true),
        ]
    )

    // MARK: - 新增聊天/办公 (WeWork)

    private static let wework = AppScanRule(
        appName: "企业微信", bundleID: "com.tencent.WeWorkMac", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 14,
        actions: [
            AppScanAction(actionID: 2001, title: "企业微信缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.WeWorkMac",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 2002, title: "企业微信日志",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.WeWorkMac",
                                     subpath: "Logs/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 2003, title: "企业微信头像(大文件)",
                          paths: [SandboxResolver.containerURL(bundleID: "com.tencent.WeWorkMac",
                                     subpath: "Data/")],
                          level: 1, recommended: false, cautionID: 2006, requireTimeFilter: true),
            AppScanAction(actionID: 2004, title: "企业微信应用缓存",
                          paths: [
                              SandboxResolver.containerURL(bundleID: "com.tencent.WeWorkMac", subpath: "Caches/fsCachedData/"),
                              "~/Library/Containers/com.tencent.WeWorkMac/Data/tmp/",
                          ],
                          level: -1, recommended: true),
        ]
    )

    // MARK: - 新增教育/输入法/音乐/视频应用

    private static let cctalk = AppScanRule(
        appName: "CCtalk", bundleID: "com.hujiang.mac.cctalk", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 18,
        actions: [
            AppScanAction(actionID: 2020, title: "CCtalk 缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.hujiang.mac.cctalk",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 2021, title: "CCtalk 日志",
                          paths: [SandboxResolver.containerURL(bundleID: "com.hujiang.mac.cctalk",
                                     subpath: "Logs/")],
                          level: -1, recommended: true),
        ]
    )

    private static let iflytekInput = AppScanRule(
        appName: "讯飞输入法", bundleID: "com.iflytek.inputmethod", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 15,
        actions: [
            AppScanAction(actionID: 2030, title: "讯飞输入法缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.iflytek.inputmethod",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 2031, title: "讯飞输入法词库",
                          paths: [SandboxResolver.containerURL(bundleID: "com.iflytek.inputmethod",
                                     subpath: "Data/")],
                          level: 1, recommended: false, requireTimeFilter: true),
        ]
    )

    private static let kwMusic = AppScanRule(
        appName: "酷我音乐", bundleID: "com.wenyu.kwplayermac", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 16,
        actions: [
            AppScanAction(actionID: 2040, title: "酷我音乐缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.wenyu.kwplayermac",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 2041, title: "酷我音乐下载(大文件)",
                          paths: [SandboxResolver.containerURL(bundleID: "com.wenyu.kwplayermac",
                                     subpath: "Data/")],
                          level: 1, recommended: false, cautionID: 2009, requireTimeFilter: true),
        ]
    )

    private static let sohuVideo = AppScanRule(
        appName: "搜狐视频", bundleID: "tv.sohu.SHPlayer", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 17,
        actions: [
            AppScanAction(actionID: 2050, title: "搜狐视频缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "tv.sohu.SHPlayer",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 2051, title: "搜狐视频日志",
                          paths: [SandboxResolver.containerURL(bundleID: "tv.sohu.SHPlayer",
                                     subpath: "Logs/")],
                          level: -1, recommended: true),
        ]
    )

    private static let baofeng = AppScanRule(
        appName: "暴风影音", bundleID: "com.baofeng.mac", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 17,
        actions: [
            AppScanAction(actionID: 2060, title: "暴风影音缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.baofeng.mac",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 2061, title: "暴风影音日志",
                          paths: [SandboxResolver.containerURL(bundleID: "com.baofeng.mac",
                                     subpath: "Logs/")],
                          level: -1, recommended: true),
        ]
    )

    private static let pptv = AppScanRule(
        appName: "PPTV", bundleID: "com.pptv.pptvmac", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 17,
        actions: [
            AppScanAction(actionID: 2070, title: "PPTV 缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.pptv.pptvmac",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
            AppScanAction(actionID: 2071, title: "PPTV 日志",
                          paths: [SandboxResolver.containerURL(bundleID: "com.pptv.pptvmac",
                                     subpath: "Logs/")],
                          level: -1, recommended: true),
        ]
    )

    private static let mkPlayer = AppScanRule(
        appName: "MKPlayer", bundleID: "com.rockysandstudio.MKPlayer", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 17,
        actions: [
            AppScanAction(actionID: 2080, title: "MKPlayer 缓存",
                          paths: [SandboxResolver.containerURL(bundleID: "com.rockysandstudio.MKPlayer",
                                     subpath: "Caches/")],
                          level: -1, recommended: true),
        ]
    )

    // MARK: - 西方应用 (Western Apps)

    private static let chrome = AppScanRule(
        appName: "Google Chrome", bundleID: "com.google.Chrome", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5001, title: "Chrome 缓存",
                          paths: ["~/Library/Caches/Google/Chrome/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5002, title: "Chrome 日志",
                          paths: ["~/Library/Application Support/Google/Chrome/chrome_debug.log"],
                          level: 0, recommended: true),
            AppScanAction(actionID: 5003, title: "Chrome 安全浏览缓存",
                          paths: ["~/Library/Application Support/Google/Chrome/SafeBrowsing"],
                          level: -1, recommended: false),
        ]
    )

    private static let firefox = AppScanRule(
        appName: "Firefox", bundleID: "org.mozilla.firefox", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5010, title: "Firefox 缓存",
                          paths: ["~/Library/Caches/Firefox/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5011, title: "Firefox 崩溃报告",
                          paths: ["~/Library/Application Support/Firefox/Crash Reports/"],
                          level: -1, recommended: true),
        ]
    )

    private static let slack = AppScanRule(
        appName: "Slack", bundleID: "com.tinyspeck.slackmacos", isSandbox: true, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5020, title: "Slack 缓存",
                          paths: ["~/Library/Containers/com.tinyspeck.slackmacos/Data/Library/Caches/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5021, title: "Slack 日志",
                          paths: ["~/Library/Containers/com.tinyspeck.slackmacos/Data/Library/Logs/"],
                          level: -1, recommended: true),
        ]
    )

    private static let zoom = AppScanRule(
        appName: "Zoom", bundleID: "us.zoom.xos", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5030, title: "Zoom 缓存",
                          paths: ["~/Library/Caches/us.zoom.xos/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5031, title: "Zoom 录制文件",
                          paths: ["~/Documents/Zoom"],
                          level: -1, recommended: false),
        ]
    )

    private static let teams = AppScanRule(
        appName: "Microsoft Teams", bundleID: "com.microsoft.teams2", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5040, title: "Teams 缓存",
                          paths: ["~/Library/Caches/com.microsoft.teams2/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5041, title: "Teams 日志",
                          paths: ["~/Library/Application Support/Microsoft/Teams/logs.txt"],
                          level: 0, recommended: true),
        ]
    )

    private static let docker = AppScanRule(
        appName: "Docker", bundleID: "com.docker.docker", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5050, title: "Docker 缓存",
                          paths: ["~/Library/Caches/com.docker.docker/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5051, title: "Docker 日志",
                          paths: ["~/Library/Containers/com.docker.docker/Data/logs/"],
                          level: -1, recommended: false),
        ]
    )

    private static let vscode = AppScanRule(
        appName: "Visual Studio Code", bundleID: "com.microsoft.VSCode", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5060, title: "VS Code 缓存",
                          paths: ["~/Library/Caches/com.microsoft.VSCode/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5061, title: "VS Code 扩展缓存",
                          paths: ["~/.vscode/extensions"],
                          level: 1, recommended: false),
            AppScanAction(actionID: 5062, title: "VS Code 日志",
                          paths: ["~/Library/Application Support/Code/logs/"],
                          level: -1, recommended: true),
        ]
    )

    private static let homebrew = AppScanRule(
        appName: "Homebrew", bundleID: "com.apple.bash", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5070, title: "Homebrew 缓存",
                          paths: ["~/Library/Caches/Homebrew/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5071, title: "Homebrew 临时文件",
                          paths: ["~/Library/Caches/Homebrew/downloads/"],
                          level: -1, recommended: true),
        ]
    )

    private static let discord = AppScanRule(
        appName: "Discord", bundleID: "com.hnc.Discord", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5080, title: "Discord 缓存",
                          paths: ["~/Library/Caches/com.hnc.Discord/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5081, title: "Discord 日志",
                          paths: ["~/Library/Application Support/discord/logs/"],
                          level: -1, recommended: true),
        ]
    )

    private static let telegram = AppScanRule(
        appName: "Telegram", bundleID: "ru.keepcoder.Telegram", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5090, title: "Telegram 缓存",
                          paths: ["~/Library/Caches/ru.keepcoder.Telegram/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5091, title: "Telegram 下载文件",
                          paths: ["~/Downloads/Telegram Desktop/"],
                          level: -1, recommended: false),
        ]
    )

    private static let steam = AppScanRule(
        appName: "Steam", bundleID: "com.valvesoftware.steam", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5110, title: "Steam 缓存",
                          paths: ["~/Library/Caches/com.valvesoftware.steam/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5111, title: "Steam 临时文件",
                          paths: ["~/Library/Application Support/Steam/steamapps/temp/"],
                          level: -1, recommended: false),
        ]
    )

    private static let adobeCreativeCloud = AppScanRule(
        appName: "Adobe Creative Cloud", bundleID: "com.adobe.acc.AdobeCreativeCloud", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5120, title: "Adobe 缓存",
                          paths: ["~/Library/Caches/com.adobe.acc.AdobeCreativeCloud/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5121, title: "Adobe 日志",
                          paths: ["~/Library/Logs/Adobe/"],
                          level: -1, recommended: true),
        ]
    )

    private static let jetbrains = AppScanRule(
        appName: "JetBrains", bundleID: "com.jetbrains.intellij", isSandbox: false, isMultiUser: false,
        categoryID: 1, subCategoryID: 3,
        actions: [
            AppScanAction(actionID: 5130, title: "JetBrains 缓存",
                          paths: ["~/Library/Caches/JetBrains/"],
                          level: -1, recommended: true),
            AppScanAction(actionID: 5131, title: "JetBrains 日志",
                          paths: ["~/Library/Logs/JetBrains/"],
                          level: -1, recommended: true),
        ]
    )
}

// MARK: - Installation Detection

extension AppScanRule {
    /// Check if this app is installed on the current system.
    /// Supports comma-separated bundle IDs (e.g. "com.alibaba.dingtalk,5ZSL2CJU2T.com.dingtalk.mac")
    /// to handle both developer-ID and App Store variants.
    public var isInstalled: Bool {
        let workspace = NSWorkspace.shared
        let bundleIDs = bundleID.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        for id in bundleIDs {
            if let appURL = workspace.urlForApplication(withBundleIdentifier: id),
               FileManager.default.fileExists(atPath: appURL.path) {
                return true
            }
        }
        return false
    }
}
