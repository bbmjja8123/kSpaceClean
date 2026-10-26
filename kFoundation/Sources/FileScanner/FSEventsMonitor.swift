// kFoundation/Sources/FileScanner/FSEventsMonitor.swift
//
// FSEvents 变更监视（Klaris Task 7 —— 画布「内容有变化——点按重新扫描」
// pill 的秒级重扫入口地基）。设计约束：
// - 回调只在会话生命周期内发生，start 幂等 / stop 后静默（测试钉住）；
// - latency 之外再加 debounce（coalesce 突发批量写入，2s 静默窗）；
// - 流创建/启动失败（沙盒无该路径读权等）静默降级——此处不抛错（监视是
//   增强，不是承诺）；`isStreamCreated` 透出真实状态，调用方
//   （AnatomyViewModel.startChangeMonitoring）据此决定是否保留监视器。
// - 生命周期（review fix：passUnretained → passRetained）：流 context 持有
//   monitor 的强引用，`context.release` 在 FSEventStreamRelease 内部归还 ——
//   回调里的 takeUnretainedValue 因此绝不可能触达已释放实例（流活着 ⇒
//   monitor 活着）。外部 stop()（或 deinit 兜底）是唯一停流入口：stop →
//   invalidate → release → context.release 归还引用 → 引用计数归零才可能
//   deinit。deinit 再入 stop()（调用方在持锁的 stop 内掉落最后一个外部强
//   引用的路径）由 NSRecursiveLock + 「先置 nil 再 release」消化。
import CoreServices
import Foundation

public final class FSEventsMonitor: @unchecked Sendable {
    private let path: String
    private let latency: TimeInterval
    private let onChange: @Sendable () -> Void
    /// 流句柄（nil = 未启动或已停止）。所有访问经 `lock` 串行化。
    private var stream: FSEventStreamRef?
    /// debounce 定时器（合并突发写入）。
    private var debounce: DispatchSourceTimer?
    /// 递归锁：stop() → FSEventStreamRelease → context.release 归还
    /// passRetained 引用可能同步触发 deinit → 再入 stop()；非递归锁会同
    /// 线程自锁死。
    private let lock = NSRecursiveLock()
    /// 流是否成功创建**并启动**（MINOR 1：`FSEventStreamStart` 返回 false
    /// 不置位，并就地清理半启动的流）。诊断/测试接缝。
    private var streamCreated = false

    /// 流是否成功创建并已启动（诊断/测试/调用方诚实降级用；线程安全）。
    public var isStreamCreated: Bool {
        lock.lock(); defer { lock.unlock() }
        return streamCreated
    }

    /// - Parameters:
    ///   - url: 监视的目录（Klaris 主画布传授权主目录根）。
    ///   - latency: FSEvents 流延迟（合并窗口下限；默认 3s）。
    ///   - onChange: 变更去抖后回调（任意线程；调用方自行跳主线程）。
    public init(watching url: URL, latency: TimeInterval = 3.0,
                onChange: @escaping @Sendable () -> Void) {
        self.path = url.path
        self.latency = latency
        self.onChange = onChange
    }

    /// 兜底停流。passRetained 下流持有 monitor 强引用 —— 能进 deinit 说明
    /// 流已被外部 stop() 释放（context.release 已归还引用）或从未建成成功；
    /// 再入的 stop() 经递归锁 + 空流守卫安全短路。
    deinit { stop() }

    /// 创建并启动流。幂等：重复调用不叠加流。创建/启动失败静默降级（见头注）。
    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard stream == nil else { return }
        // passRetained（review fix）：流持有 monitor。引用由 context.release
        // 在 FSEventStreamRelease 内归还；创建失败的分支需手动平衡（见下）。
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<FSEventsMonitor>.fromOpaque(info).release()
            },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<FSEventsMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.scheduleDebounce()
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags)
        else {
            // 沙盒/权限不足：静默降级。流未建成 → context.release 永远不会
            // 被 FSEvents 调用，passRetained 的引用在此手动平衡，否则 self
            // 永不 dealloc。
            if let info = context.info {
                Unmanaged<FSEventsMonitor>.fromOpaque(info).release()
            }
            return
        }
        self.stream = stream
        // macOS 13+：dispatch queue 版调度（runloop 版已 deprecated）。
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        // MINOR 1：启动失败同样视为「未创建」——就地清理半启动的流（其
        // release 会经 context.release 归还 passRetained 引用），不置位。
        guard FSEventStreamStart(stream) else {
            self.stream = nil
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        streamCreated = true
    }

    /// 停流并静默后续回调（stop 后再变更不得触发 onChange —— 测试钉住）。
    /// 幂等；start() 可在其后再次调用（重新创建流）。
    public func stop() {
        lock.lock(); defer { lock.unlock() }
        debounce?.cancel(); debounce = nil
        streamCreated = false
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        // 先置 nil 再 release：release 触发的 context.release 可能同步归还
        // passRetained 引用并立刻 deinit → 再入本方法，届时 stream 已为 nil
        // （配合递归锁安全短路）。
        self.stream = nil
        FSEventStreamRelease(stream)
    }

    /// 变更去抖：2s 静默窗内的连续事件只回调一次（coalesce 批量写入）。
    private func scheduleDebounce() {
        lock.lock(); defer { lock.unlock() }
        debounce?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2.0)
        timer.setEventHandler { [onChange] in onChange() }
        timer.resume()
        debounce = timer
    }
}
