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
import FileScanner

extension AnatomyViewModel {

    // MARK: - Phase 状态机

    /// hero 扫描进度态（spec §5）。
    public enum ScanPhase: Equatable {
        /// 尚未扫描 / 已取消。
        case idle
        /// 扇出或引擎扫描进行中；`path` 为空表示尚无当前路径（准备段）。
        case scanning(progress: Double, path: String)
        /// 上一轮扫描正在收尾（用户已取消 / 重扫已排队等待落定）——
        /// P2 final I3 的诚实过渡态：既不伪造进度，也不静默吞掉重扫。
        case stopping
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
    /// 另订阅 `isRunning` 下降沿：`.stopping` 过渡态（I3）落定后回 idle。
    public func bindCoordinator(_ coordinator: CanvasScanCoordinator) {
        canvasCoordinator = coordinator
        coordinator.$groups
            .sink { [weak self] groups in
                Task { @MainActor in
                    guard let self, let active = self.canvasCoordinator,
                          active.isRunning, active === coordinator,
                          case .scanning(let current, let path) = self.scanPhase else { return }
                    // fix r1 ③：进度只单调递增（groups 计数回退时不倒退）。
                    let next = Self.fanOutProgress(groupCount: groups.count)
                    guard next > current else { return }
                    self.scanPhase = .scanning(progress: next, path: path)
                }
            }
            .store(in: &canvasCancellables)
        // I3（P2 final）：扇出管线停止（含取消后的自然收尾）→ 若 hero 正处
        // 「正在停止」过渡态则回 idle。兜底通道（常规收尾由 runCanvasScan
        // 被取消的 continuation 就地复位 —— 它恰在 isRunning 落 false 后
        // 恢复，不会被观察到 stale 的 .stopping）。
        coordinator.$isRunning
            .removeDuplicates()
            .sink { [weak self] running in
                Task { @MainActor in
                    guard let self, self.canvasCoordinator === coordinator, !running,
                          case .stopping = self.scanPhase else { return }
                    self.scanPhase = .idle
                }
            }
            .store(in: &canvasCancellables)
    }

    /// 注入扫描页 VM（RootView onAppear 晚绑定）。
    /// - 引擎扫描进行中：hero 镜像引擎进度（spec §5 进度态的数据源）。
    /// - 引擎扫描结束（true→false）：归因 report 刷新 —— P1 修复波机制，
    ///   所有扫描入口（⌘N/⌘R、菜单栏 quickScan）都收敛到同一个 startScan。
    /// （internal：`ScanResultsViewModel` 是 app 内部类型，不能跨 public 泄露。）
    /// 幂等：重复 bind 先撤旧订阅再挂新的（fix r1 ⑤——重复 bind 不累积）。
    func bindScanViewModel(_ vm: ScanResultsViewModel) {
        scanVMBindCancellables.removeAll()
        // C1（P2 final）：统一扫描入口 —— runCanvasScan 先经这里绑定的
        // 扫描页 VM await 引擎扫描完成，再对新鲜树做归因/检测器扇出。
        scanVM = vm

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
                        // Task 7：扫描完成后启动主目录变更监视（幂等 —— 已有
                        // 监视器则不重复启动）。container-only 时 grantedRoot
                        // 为 nil → 不启动（pill 不出现，诚实降级）；流创建失败
                        // 同样无感（监视是增强，不是承诺）。
                        self.startChangeMonitoring(
                            root: AppScope.shared.capability.grantedRoot)
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

    /// hero「重新扫描」/ ⌘R / 菜单栏 quickScan / onboarding 首扫的**唯一**
    /// 画布扫描入口（C1）。fire-and-forget；测试可直接 await `runCanvasScan()`。
    ///
    /// 重入语义：
    /// - 活跃扫描期（`isRunning` 且非 `.stopping`）的重复触发 → 忽略
    ///   （【交接 T2】isRunning 守卫，既有契约）；
    /// - `.stopping` 过渡期（用户已取消、上一轮管线正在收尾）的重扫 →
    ///   排队等落定后真实启动 —— 取消后立即重扫绝不静默丢弃（I3）。
    public func startScan() {
        // Task 7：重扫即消费待重扫标志 —— 无论本次触发最终走新扇出还是
        // 撞上活跃扫描守卫被忽略，「用户已要求重扫」的事实都成立，pill
        // 不应残留。置位于动作入口（brief 口径）。
        clearPendingChanges()
        guard let coordinator = canvasCoordinator else { return }
        if coordinator.isRunning, scanPhase != .stopping { return }
        canvasScanTask?.cancel()
        canvasScanTask = Task { await runCanvasScan() }
    }

    /// hero「取消」—— 取消扇出 Task；不伪造完成态，也不把取消当成功写
    /// canvasReport。管线尚未落定时进入 `.stopping` 诚实过渡态（I3），
    /// 由 bindCoordinator 的 isRunning 下降沿订阅回 idle。
    public func cancelScan() {
        canvasScanTask?.cancel()
        canvasScanTask = nil
        if canvasCoordinator?.isRunning == true {
            if case .scanning = scanPhase {
                scanPhase = .stopping
            }
        } else if scanPhase.isScanning {
            scanPhase = .idle
        }
    }

    // MARK: - FSEvents 变更监视（Task 7）

    /// 首扫完成后启动主目录变更监视。沙盒 container-only 时 grantedRoot
    /// 为 nil → 不启动（pill 不出现，诚实降级）；流创建/启动失败同样降级
    /// ——不保留监视器，pill 不会出现，也绝不静默承诺「会感知变更」。
    /// 幂等：监视器已在且流健康时不重建（整个会话一根流，重扫不重启监视）；
    /// 上次流创建失败的（如授权前的探测）在下次扫描完成后自动重试。
    public func startChangeMonitoring(root: URL?) {
        guard let root else { return }
        if let existing = fsMonitor, existing.isStreamCreated { return }
        let monitor = FSEventsMonitor(watching: root) { [weak self] in
            Task { @MainActor in self?.hasPendingChanges = true }
        }
        monitor.start()
        // MINOR 2：消费 isStreamCreated —— 创建/启动失败不保留监视器
        // （下次扫描完成后重试），降级以 pill 缺席呈现，不弹 UI。
        fsMonitor = monitor.isStreamCreated ? monitor : nil
    }

    /// 重扫入口（startScan）消费待重扫标志 —— pill 随之消失。
    public func clearPendingChanges() { hasPendingChanges = false }

    /// 可等待的扇出扫描管线（startScan 的实现体）。
    ///
    /// C1（P2 final）统一扫描入口，三段：
    /// 1. 若上一轮扇出仍在收尾（`.stopping` 排队的重扫）→ 等其落定；
    /// 2. await 引擎扫描完成（沿用 SmartCareOrchestrator 的轮询模式，
    ///    进度经 bindScanViewModel 的镜像上 hero）；
    /// 3. 对**新鲜树**做归因 + 检测器扇出 —— 首启/重扫时画布组不再吃
    ///    空树的哑火（旧实现只扇出、从不跑引擎，categoriesProvider 读
    ///    到的是空 categories → 零 cause 组）。
    func runCanvasScan() async {
        guard let coordinator = canvasCoordinator else { return }
        // 段 1：上一轮管线正在收尾 —— 诚实呈现「正在停止」，不静默丢弃。
        if coordinator.isRunning {
            if case .scanning = scanPhase { scanPhase = .stopping }
            while coordinator.isRunning {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if Task.isCancelled { return }
            }
        }
        // 段 2：引擎扫描（扫描页 VM）。已在扫描中（如 ⌘N 先到）则顺延等待；
        // 未绑定（测试/降级路径）直接跳到扇出 —— 保持既有测试契约。
        if let scanVM {
            scanVM.startScan()
            while scanVM.isScanning {
                // 进度由 bindScanViewModel 的镜像订阅驱动（engineScanMirrored）。
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
            }
            // P3 诚实性：引擎扫描因 scope 跳过的根上画布诊断（禁止静默
            // 丢弃 —— MAS 未授权时用户必须能看见"哪些区域没扫"）。
            let skipped = await scanVM.engine?.lastScopeCoverage()
            if let regions = skipped?.skippedRegions.map(\.displayName), !regions.isEmpty {
                canvasCoordinator?.noteSkippedRegions(regions)
            }
        }
        guard !Task.isCancelled else { return }
        scanPhase = .scanning(progress: 0, path: "")
        // 段 3：扇出消费**此刻**的新鲜树（provider 在扫描完成后才求值）。
        let scope = canvasScopeProvider?() ?? Self.defaultScope(
            categories: categoriesProvider?() ?? [],
            housekeepingHome: housekeepingHomeProvider())
        let report = await coordinator.runScan(scope: scope)
        guard !Task.isCancelled else {
            // I3：取消的收尾 —— 本 continuation 恰在 isRunning 落 false 之后
            // 恢复，就地复位 .stopping（外部观察者不会看到过期的停止态）。
            // 仅在仍处 .stopping 时写（排队重扫的 .scanning 绝不被回退）。
            if case .stopping = scanPhase { scanPhase = .idle }
            return
        }
        // 【交接 T2】消费 runScan 返回值前先查 isRunning —— 重入返回的
        // 增量报告 uncovered/snapshots 为 nil，不可当完成态渲染。
        // 本 VM 用 isRunning 状态机规避：只有真实跑完（isRunning 已落 false）
        // 的报告才写 canvasReport。
        guard !coordinator.isRunning else { return }
        canvasReport = report
        // T6：新扫描 = 新事实 —— 下钻勾选态缓存整体作废（旧组已不存在，
        // 带着旧勾选进新下钻页是陈旧承诺）。扫描期间下钻不可达（画布禁用）。
        drillDownModels.removeAll()
        scanPhase = .done
        // 归因刷新：coordinator 不回传原始归因清单，而预演 sheet 的
        // attributionLookup（P1 final F3a）依赖 report.allAttributions。
        await refresh()
    }

    // MARK: - 派生

    /// 画布组列表：
    /// - 完成/空闲态 → `canvasReport.groups`（totalBytes 降序）；
    /// - 扫描中 → 上一次报告的组**保留**（不清空，渲染层变灰）+ 协调器增量
    ///   产出的新组；同 GroupKind 的旧组被新组**替换**（fix r1 ②：新扫描的
    ///   组就是最新事实，且保证 ForEach id 唯一——旧报告组与增量组并存时
    ///   同 kind 出现两次会让 List identity 冲突、展开态错乱）。
    public var displayGroups: [CanvasGroup] {
        if scanPhase.isScanning, let coordinator = canvasCoordinator,
           coordinator.isRunning {
            let incremental = coordinator.groups
            let carried = (canvasReport?.groups ?? []).filter { old in
                !incremental.contains { $0.id == old.id }
            }
            return carried + incremental
        }
        return canvasReport?.groups ?? []
    }

    // MARK: hero 进度态数据源（fix r1 ②——取消按钮的诚实可见性）

    /// hero 进度态的来源：`.fanOut` = 画布自己的扇出扫描（取消按钮有效）；
    /// `.engine` = 扫描页引擎扫描的镜像（取消按钮对引擎无效，视图隐藏）。
    public enum ScanSource { case fanOut, engine }

    /// 当前扫描中 hero 进度态的数据源。扇出优先（它有真取消句柄）；
    /// 非扫描期返回 `.fanOut`（`showsScanCancel` 会因 `isScanning == false` 恒 false）。
    public var activeScanSource: ScanSource {
        if canvasCoordinator?.isRunning == true { return .fanOut }
        if engineScanMirrored { return .engine }
        return .fanOut
    }

    /// hero「取消」按钮是否应显示（fix r1 ②）：只在扇出扫描中可见——
    /// 引擎镜像态取消按钮对引擎扫描无效，显示即误导（点了还闪回）。
    public var showsScanCancel: Bool {
        scanPhase.isScanning && activeScanSource == .fanOut
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
    /// 检测器吃各自工具页同源的默认授权目录（PowerScope-honest 探测，
    /// 无权限时为空 → coordinator 跳过对应段，不出空组）。家务三组（Task 8）
    /// 吃 `housekeepingHome`（grantedRoot；container-only 为 nil → 上诊断）。
    static func defaultScope(categories: [ScanCategory],
                             housekeepingHome: URL?) -> CanvasScanScope {
        let capability = AppScope.shared.capability
        return CanvasScanScope(
            categories: categories,
            duplicateRoots: DuplicateViewModel.defaultScanPaths(capability: capability),
            photoDirectories: PhotoSimilarityScanner.candidateDirectories(capability: capability),
            largeFileRoots: [FileManager.default.homeDirectoryForCurrentUser],
            housekeepingHome: housekeepingHome)
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
