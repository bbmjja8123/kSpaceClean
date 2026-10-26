// kFoundation/Sources/FileScanner/FSEventsMonitor.swift
//
// FSEvents 变更监视（Klaris Task 7 —— 画布「内容有变化——点按重新扫描」
// pill 的秒级重扫入口地基）。设计约束：
// - 回调只在会话生命周期内发生，start 幂等 / stop 后静默（测试钉住）；
// - latency 之外再加 debounce（coalesce 突发批量写入，2s 静默窗）；
// - 流创建失败（沙盒无该路径读权等）静默降级——调用方以画布诊断补诚实
//   提示，此处不抛错（监视是增强，不是承诺）。
// - 生命周期配对：`Unmanaged.passUnretained(self)` 进流 context + deinit
//   stop()。passUnretained 不持有自身，deinit 先停流再释放，回调不会再
//   触达已释放实例（stop 在 stream release 前完成 invalidate）。
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
    private let lock = NSLock()
    /// 流是否成功创建（诊断/测试接缝：沙盒宿主内 FSEventStreamCreate 可能
    /// 失败，监视是增强不是承诺 —— 调用方据此诚实降级，不静默承诺）。
    private var streamCreated = false

    /// 流是否成功创建并已启动（诊断/测试用；线程安全）。
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

    deinit { stop() }

    /// 创建并启动流。幂等：重复调用不叠加流。创建失败静默降级（见头注）。
    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
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
        else { return }   // 沙盒/权限不足：静默降级
        self.stream = stream
        streamCreated = true
        // macOS 13+：dispatch queue 版调度（runloop 版已 deprecated）。
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
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
        FSEventStreamRelease(stream)
        self.stream = nil
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
