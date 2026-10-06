// kWise/Features/Anatomy/AnatomyScanState.swift
//
// 主画布扫描进度态（P2 T3，spec §5「扫描即动作，非页面」）：
// - `ScanPhase`：hero 的状态机 —— idle / scanning(progress, path) / done。
//   hero 在 idle/done 呈标题+构成条+按钮行；scanning 呈进度条+当前路径+取消。
// - `startScan()`：扇出 coordinator（归因 → 重复 → 照片 → 大文件），完成时
//   写 `canvasReport` 并落 `.done`。
// - `bindScanViewModel(_:)`：Combine 订阅扫描页引擎 `isScanning` —— 上升沿
//   把引擎进度镜像进 hero 进度态（`$progress`/`$currentPath`），下降沿触发
//   归因 report 刷新（P1 修复波机制自 RootView 的 .onChange 迁入 VM）。
//   【交接 T2】消费 `runScan` 返回值前必须先查 `isRunning`：重入返回的
//   增量报告 uncovered/snapshots 为 nil，不可当完成态渲染 —— 本 VM 的
//   isRunning 状态机天然规避（见 `runCanvasScan`）。
import Foundation
import Combine
import SwiftUI

extension AnatomyViewModel {

    // MARK: - Phase 状态机

    /// hero 扫描进度态（spec §5）。
    public enum ScanPhase: Equatable {
        /// 尚未扫描 / 已取消。
        case idle
        /// 扇出或引擎扫描进行中；`path` 为空表示尚无当前路径（准备段）。
        case scanning(progress: Double, path: String)
        /// 最近一次扇出扫描已完成。
        case done

        /// 当前是否处于扫描中（视图据此切换 hero 两态、画布变灰）。
        public var isScanning: Bool {
            if case .scanning = self { return true }
            return false
        }
    }

    // MARK: - 绑定

    /// 注入画布扇出协调器（RootView onAppear 晚绑定，同 rebindCategories 模式）。
    /// 同时订阅协调器的增量组产出：每组完成即推进粗粒度里程碑进度 ——
    /// 归因/重复/照片/大文件四段，画布不清空、hero 进度不撒谎。
    public func bindCoordinator(_ coordinator: CanvasScanCoordinator) {
        canvasCoordinator = coordinator
        coordinator.$groups
            .sink { [weak self] groups in
                Task { @MainActor in
                    guard let self, let active = self.canvasCoordinator,
                          active.isRunning, active === coordinator,
                          case .scanning(_, let path) = self.scanPhase else { return }
                    self.scanPhase = .scanning(
                        progress: Self.fanOutProgress(groupCount: groups.count),
                        path: path)
                }
            }
            .store(in: &canvasCancellables)
    }

    /// 注入扫描页 VM（RootView onAppear 晚绑定）。
    /// - 引擎扫描进行中：hero 镜像引擎进度（spec §5 进度态的数据源）。
    /// - 引擎扫描结束（true→false）：归因 report 刷新 —— P1 修复波机制，
    ///   所有扫描入口（⌘N/⌘R、菜单栏 quickScan）都收敛到同一个 startScan。
    /// （internal：`ScanResultsViewModel` 是 app 内部类型，不能跨 public 泄露。）
    func bindScanViewModel(_ vm: ScanResultsViewModel) {
        vm.isScanningPublisher
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self, weak vm] scanning in
                Task { @MainActor in
                    guard let self, let vm else { return }
                    self.engineScanMirrored = scanning
                    if scanning {
                        self.scanPhase = .scanning(progress: vm.progress,
                                                   path: vm.currentPath)
                    } else {
                        // 下降沿：归因刷新（P1 修复波）。若画布扇出恰在
                        // 进行中，phase 归扇出管线管，这里只刷归因。
                        if self.canvasCoordinator?.isRunning != true,
                           case .scanning = self.scanPhase {
                            self.scanPhase = self.canvasReport != nil ? .done : .idle
                        }
                        await self.refresh()
                    }
                }
            }
            .store(in: &scanVMBindCancellables)

        // 引擎进度/当前路径 → hero 进度条（仅镜像期间生效）。
        vm.$progress
            .combineLatest(vm.$currentPath)
            .sink { [weak self] progress, path in
                Task { @MainActor in
                    guard let self, self.engineScanMirrored else { return }
                    self.scanPhase = .scanning(progress: progress, path: path)
                }
            }
            .store(in: &scanVMBindCancellables)
    }

    /// 注入/覆盖扫描范围（测试接缝；生产走 `defaultScope`）。
    public func rebindScope(_ provider: @escaping () -> CanvasScanScope) {
        canvasScopeProvider = provider
    }

    // MARK: - 动作

    /// hero「重新扫描」/ ⌘R 的画布扫描入口。fire-and-forget；测试可直接
    /// await `runCanvasScan()`。重入守卫见 `runCanvasScan`。
    public func startScan() {
        guard let coordinator = canvasCoordinator, !coordinator.isRunning else { return }
        canvasScanTask?.cancel()
        canvasScanTask = Task { await runCanvasScan() }
    }

    /// hero「取消」—— 取消扇出 Task；进度态回到 idle（不伪造完成态，
    /// 也不把取消当成功写 canvasReport）。
    public func cancelScan() {
        canvasScanTask?.cancel()
        canvasScanTask = nil
        if case .scanning = scanPhase {
            scanPhase = .idle
        }
    }

    /// 可等待的扇出扫描管线（startScan 的实现体）。
    func runCanvasScan() async {
        guard let coordinator = canvasCoordinator, !coordinator.isRunning else { return }
        scanPhase = .scanning(progress: 0, path: "")
        let scope = canvasScopeProvider?() ?? Self.defaultScope(
            categories: categoriesProvider?() ?? [])
        let report = await coordinator.runScan(scope: scope)
        guard !Task.isCancelled else {
            scanPhase = .idle
            return
        }
        // 【交接 T2】消费 runScan 返回值前先查 isRunning —— 重入返回的
        // 增量报告 uncovered/snapshots 为 nil，不可当完成态渲染。
        // 本 VM 用 isRunning 状态机规避：只有真实跑完（isRunning 已落 false）
        // 的报告才写 canvasReport。
        guard !coordinator.isRunning else { return }
        canvasReport = report
        scanPhase = .done
        // 归因刷新：coordinator 不回传原始归因清单，而预演 sheet 的
        // attributionLookup（P1 final F3a）依赖 report.allAttributions。
        await refresh()
    }

    // MARK: - 派生

    /// 画布组列表：
    /// - 完成/空闲态 → `canvasReport.groups`（totalBytes 降序）；
    /// - 扫描中 → 上一次报告的组**保留**（不清空，渲染层变灰）+ 协调器
    ///   增量产出的新组（spec §5：分组区淡出但不消失）。
    public var displayGroups: [CanvasGroup] {
        if scanPhase.isScanning, let coordinator = canvasCoordinator,
           coordinator.isRunning {
            return (canvasReport?.groups ?? []) + coordinator.groups
        }
        return canvasReport?.groups ?? []
    }

    /// hero「安全快捷回收 · 预计 X」的估算 —— 只累计绿徽（✓ 可回收）条目的
    /// 诚实字节；蓝/橙/红/灰条目一律不计入（不夸大、不倒逼）。
    public var quickCleanEstimate: Int64 {
        displayGroups.reduce(Int64(0)) { total, group in
            total + group.entries
                .filter { $0.badge == .recyclable }
                .reduce(Int64(0)) { $0 + $1.bytes }
        }
    }

    /// 扇出粗粒度进度：每完成一段（组产出）推进 0.25，封顶 0.9 —— 完成的
    /// 100% 只在 .done 落定时出现（诚实进度，绝不提前宣称完成）。
    static func fanOutProgress(groupCount: Int) -> Double {
        min(0.9, Double(groupCount) * 0.25)
    }

    /// 生产扫描范围：归因吃扫描树分类（rebindCategories 注入的 provider），
    /// 三个检测器吃各自工具页同源的默认授权目录（PowerScope-honest 探测，
    /// 无权限时为空 → coordinator 跳过对应段，不出空组）。
    static func defaultScope(categories: [ScanCategory]) -> CanvasScanScope {
        let capability = AppScope.shared.capability
        return CanvasScanScope(
            categories: categories,
            duplicateRoots: DuplicateViewModel.defaultScanPaths(capability: capability),
            photoDirectories: PhotoSimilarityScanner.candidateDirectories(capability: capability),
            largeFileRoots: [FileManager.default.homeDirectoryForCurrentUser])
    }
}

// MARK: - 构成条（spec §3.1）

/// hero 构成条的一片：按组着色、按 totalBytes 配比。
public struct CompositionSlice: Identifiable {
    public let id: GroupKind
    /// 占画布组总字节的比例（0...1）。
    public let fraction: Double
    public let color: Color
}

extension AnatomyViewModel {

    /// hero 构成条数据源：canvasReport 的组按 totalBytes 配比、按组内最大
    /// 条目的徽章着色（绿=可回收为主 / 蓝=迁出 / 橙=注意 / 红=数据 / 灰=不动）。
    public var compositionSlices: [CompositionSlice] {
        let groups = canvasReport?.groups ?? []
        let total = groups.reduce(Int64(0)) { $0 + $1.totalBytes }
        guard total > 0 else { return [] }
        return groups.map { group in
            CompositionSlice(
                id: group.id,
                fraction: Double(group.totalBytes) / Double(total),
                color: CanvasGroupCardCopy.color(
                    for: group.entries.first?.badge ?? .leaveAlone))
        }
    }
}
