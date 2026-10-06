// kWise/Features/Anatomy/CanvasPlusMenu.swift
//
// P2 T4 — hero「+」菜单 + 整窗拖放粉碎覆盖层（spec §3.8 / 决策 ⓒ）。
// 红线：这里只负责「表达意图」与「打开粉碎窗 / 预填 URL」——粉碎自身的
// DELETE 确认链（DangerousConfirmDialog → shredStaged）在 ShredderView，
// 本文件不触碰、也不绕过。破坏性覆盖层只在拖拽悬停期间出现（意图表达后），
// 松开即随状态机归零淡出（0.2s）。
import SwiftUI
import UniformTypeIdentifiers
import DesignSystem

// MARK: - 「+」菜单

/// hero「+」菜单的注册项。顺序即菜单顺序（spec §3.8）。
enum CanvasPlusMenuItem: String, CaseIterable, Identifiable {
    /// 粉碎窗（RootView 挂 sheet，graph.shredderVM() 现有装配复用）。
    case shredder
    /// 旧版空间地图（W4 退役前的逃生口，走既有 .spaceMap 导航）。
    case spaceMapLegacy
    /// 归因规则清单（规则 corpus 的诚实披露页）。
    case attributionRules

    var id: String { rawValue }

    /// xcstrings key —— 测试钉 key，文案改动不破坏映射契约。
    var titleKey: String {
        switch self {
        case .shredder: return "canvas.plusMenu.shredder"
        case .spaceMapLegacy: return "canvas.plusMenu.spaceMapLegacy"
        case .attributionRules: return "canvas.plusMenu.attributionRules"
        }
    }

    var systemImage: String {
        switch self {
        case .shredder: return "flame"
        case .spaceMapLegacy: return "circle.hexagongrid.circle"
        case .attributionRules: return "list.bullet.rectangle.portrait"
        }
    }

    var title: String {
        String(localized: String.LocalizationValue(titleKey))
    }
}

/// 菜单项 → 动作的路由。测试钉住分发不串线；视图只消费。
struct CanvasPlusMenuActions {
    var onShredder: () -> Void
    var onSpaceMapLegacy: () -> Void
    var onAttributionRules: () -> Void

    func callAsFunction(_ item: CanvasPlusMenuItem) {
        switch item {
        case .shredder: onShredder()
        case .spaceMapLegacy: onSpaceMapLegacy()
        case .attributionRules: onAttributionRules()
        }
    }
}

/// hero 按钮行的「+」Menu（替换 T3 的 plus.circle 静态占位）。
struct CanvasPlusMenu: View {
    let actions: CanvasPlusMenuActions

    var body: some View {
        Menu {
            ForEach(CanvasPlusMenuItem.allCases) { item in
                Button {
                    actions(item)
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 16))
                .foregroundStyle(Color.textSecondary)
        }
        .help(String(localized: String.LocalizationValue("canvas.hero.plusMenu.help")))
    }
}

// MARK: - 整窗拖放粉碎状态机

/// 拖拽悬停 → 覆盖层点亮；松开 → 校验后转发粉碎窗。
/// 全有或全无：只要批次里有一个非普通文件，整批拒绝 —— 破坏性 UI 只接受
/// 完整合法批次，不做部分转发。
@MainActor
final class DragToShredModel: ObservableObject {
    /// 拖拽悬停在窗口上（覆盖层可见性；onDrop 的 isTargeted 绑定点亮）。
    @Published var isHovering = false
    /// 转发目标。RootView 注入：预填 `graph.shredderVM()` + 打开粉碎窗 sheet。
    var onShredRequested: ([URL]) -> Void = { _ in }

    /// 投放落定。仅当全部为普通文件时返回 true 并转发粉碎窗。
    @discardableResult
    func urlsDropped(_ urls: [URL]) -> Bool {
        defer { isHovering = false }
        guard !urls.isEmpty, urls.allSatisfy(Self.isRegularFile) else { return false }
        onShredRequested(urls)
        return true
    }

    /// 普通文件判定：file:// 且资源探测为常规文件。目录、网页 promise、
    /// 探测失败的条目一律按拒绝处理（破坏性入口宁拒勿收）。
    private static func isRegularFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile ?? false
    }
}

/// NSItemProvider → URL 的共用解析（粉碎窗内部 drop 与整窗 drop 同源）。
enum FileURLDropResolver {
    /// 返回是否接受这次拖放（存在 fileURL provider 才接受）；URL 异步解析，
    /// 完成后在主队列回调。
    static func resolve(_ providers: [NSItemProvider],
                        completion: @escaping @MainActor ([URL]) -> Void) -> Bool {
        var sawFileURL = false
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers
        where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            sawFileURL = true
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        guard sawFileURL else { return false }
        group.notify(queue: .main) {
            Task { @MainActor in completion(urls) }
        }
        return true
    }
}

// MARK: - 悬停覆盖层 + 整窗挂载

/// 「松开以粉碎」覆盖层：半透明底 + 虚线框。只在意图表达后出现。
struct ShredDropOverlay: View {
    var body: some View {
        ZStack {
            Color.bgPrimary.opacity(0.85)
                .ignoresSafeArea()
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.danger)
                Text(String(localized: String.LocalizationValue("canvas.shred.dropOverlay")))
                    .font(AppFont.title3)
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .strokeBorder(Color.danger.opacity(0.7),
                              style: StrokeStyle(lineWidth: 2, dash: [8]))
                .padding(AppSpacing.lg)
        )
    }
}

/// 整窗挂载：`onDrop(of: [.fileURL])` 覆盖整个内容区 + 悬停覆盖层
/// （0.2s 淡入淡出，transition 自带动画，不波及宿主其它视图）。
struct DragToShredOverlay: ViewModifier {
    @ObservedObject var model: DragToShredModel

    func body(content: Content) -> some View {
        content
            .overlay {
                if model.isHovering {
                    ShredDropOverlay()
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $model.isHovering) { providers in
                FileURLDropResolver.resolve(providers) { urls in
                    model.urlsDropped(urls)
                }
            }
    }
}
