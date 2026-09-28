// kWise/Features/Attribution/BlackBoxMath.swift
//
// 黑盒数学（spec §4.2 地基公式）：
//   黑盒 ≈ 卷用量 − 可见文件合计；分解 = APFS 快照(计数) + 系统保留(残差桶)
// 红线：数据缺失 → .insufficientData（residual = 0 但状态明示），
//       永远不用 0 冒充「没有黑盒」。
import Foundation

public struct BlackBoxBreakdown: Equatable, Sendable {
    public enum Status: String, Sendable {
        case reconciled
        case negativeResidual
        case insufficientData
    }

    public let usedBytes: Int64?
    public let visibleBytes: Int64
    public let residualBytes: Int64
    public let snapshotCount: Int
    public let status: Status

    public init(usedBytes: Int64?, visibleBytes: Int64,
                residualBytes: Int64, snapshotCount: Int, status: Status) {
        self.usedBytes = usedBytes
        self.visibleBytes = visibleBytes
        self.residualBytes = residualBytes
        self.snapshotCount = snapshotCount
        self.status = status
    }
}

public enum BlackBoxMath {
    public static func reconcile(usedBytes: Int64?, visibleBytes: Int64,
                                 snapshotCount: Int) -> BlackBoxBreakdown {
        guard let usedBytes else {
            return BlackBoxBreakdown(usedBytes: nil, visibleBytes: visibleBytes,
                                     residualBytes: 0, snapshotCount: snapshotCount,
                                     status: .insufficientData)
        }
        let residual = usedBytes - visibleBytes
        if residual < 0 {
            return BlackBoxBreakdown(usedBytes: usedBytes, visibleBytes: visibleBytes,
                                     residualBytes: 0, snapshotCount: snapshotCount,
                                     status: .negativeResidual)
        }
        return BlackBoxBreakdown(usedBytes: usedBytes, visibleBytes: visibleBytes,
                                 residualBytes: residual, snapshotCount: snapshotCount,
                                 status: .reconciled)
    }
}
