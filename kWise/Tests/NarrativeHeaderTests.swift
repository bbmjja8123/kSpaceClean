// kWise/Tests/NarrativeHeaderTests.swift
//
// P2 T7 — 历史叙事头（「这周你回收了 X」+ 磁盘对比 sub + 打卡一行小字）。
// 钉住：周聚合数字正确 / 空历史诚实零 / 打卡行 nil 安全 / 磁盘对比诚实变体
// （C-5：不夸大不虚构）/ 月报退役后 TimelineViewModel 的组装面。
import XCTest
import CoreData
@testable import kWise

@MainActor
final class NarrativeHeaderTests: XCTestCase {

    private var persistence: PersistenceController!
    private var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        context = persistence.viewContext
    }

    override func tearDown() {
        context = nil
        persistence = nil
        super.tearDown()
    }

    @discardableResult
    private func record(size: Int64, cleanedAt: Date) -> CleanupHistoryItem {
        let item = CleanupHistoryItem(context: context)
        item.id = UUID()
        item.path = "/tmp/\(UUID().uuidString)"
        item.size = size
        item.cleanedAt = cleanedAt
        item.riskLevel = "recommended"
        item.categoryID = "system.cache"
        return item
    }

    private func day(_ offset: Int, from now: Date,
                     calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    private func sample(_ offsetDays: Int, used: Int64, from now: Date,
                        capacity: Int64 = 500_000_000_000,
                        calendar: Calendar = .current) -> DiskSample {
        DiskSample(
            day: DiskSampleStore.dayKey(for: day(offsetDays, from: now, calendar: calendar),
                                        calendar: calendar),
            usedBytes: used,
            totalBytes: capacity
        )
    }

    // MARK: - 周聚合数字正确

    func testWeeklyAggregationCountsOnlyTrailingSevenDays() {
        let now = Date()
        record(size: 4_000_000_000, cleanedAt: now)
        record(size: 8_400_000_000, cleanedAt: day(-2, from: now))
        record(size: 99_000_000_000, cleanedAt: day(-10, from: now))

        let header = NarrativeHeaderModel.build(
            records: persistence.fetchHistory(limit: 0),
            samples: [],
            streak: StreakState(),
            now: now
        )

        XCTAssertTrue(header.headline.contains("12.4"),
                      "周聚合应为 12.4 GB，实际: \(header.headline)")
        XCTAssertTrue(header.headline.contains("GB"))
        XCTAssertTrue(header.headline.contains("回收"))
        XCTAssertFalse(header.headline.contains("99"),
                       "7 天窗口外的清理不得计入周聚合")
    }

    // MARK: - 空历史诚实零

    func testEmptyHistoryIsHonestZero() {
        let header = NarrativeHeaderModel.build(
            records: [], samples: [], streak: StreakState()
        )

        XCTAssertEqual(header.headline, "这周还没有清理记录",
                       "空历史必须诚实说「还没有」，不得虚构回收量")
        XCTAssertFalse(header.headline.contains("GB"))
    }

    // MARK: - 磁盘对比 sub（诚实变体）

    func testSubReportsLighterThanLastWeek() {
        let now = Date()
        let header = NarrativeHeaderModel.build(
            records: [],
            samples: [
                sample(-8, used: 100_000_000_000, from: now),
                sample(0, used: 94_000_000_000, from: now),
            ],
            streak: StreakState(),
            now: now
        )

        XCTAssertTrue(header.sub.contains("轻 6%"),
                      "100 GB → 94 GB 应报告「轻 6%」，实际: \(header.sub)")
    }

    func testSubIsHonestWhenDiskIsHeavier() {
        let now = Date()
        let header = NarrativeHeaderModel.build(
            records: [],
            samples: [
                sample(-8, used: 90_000_000_000, from: now),
                sample(0, used: 100_000_000_000, from: now),
            ],
            streak: StreakState(),
            now: now
        )

        XCTAssertTrue(header.sub.contains("重"),
                      "磁盘变重必须如实报告，不得粉饰，实际: \(header.sub)")
    }

    func testSubReportsFlatWhenUnchanged() {
        let now = Date()
        let header = NarrativeHeaderModel.build(
            records: [],
            samples: [
                sample(-8, used: 100_000_000_000, from: now),
                sample(0, used: 100_000_000_000, from: now),
            ],
            streak: StreakState(),
            now: now
        )

        XCTAssertTrue(header.sub.contains("持平"), "实际: \(header.sub)")
    }

    func testSubIsHonestWhenSamplesInsufficient() {
        let header = NarrativeHeaderModel.build(
            records: [], samples: [], streak: StreakState()
        )

        XCTAssertTrue(header.sub.contains("采样不足"),
                      "样本不足必须诚实说明，不得编造对比，实际: \(header.sub)")
    }

    // MARK: - 打卡行 nil 安全

    func testStreakLinePresentWhenStreakActive() {
        var state = StreakState()
        state.currentStreak = 5

        let header = NarrativeHeaderModel.build(
            records: [], samples: [], streak: state
        )

        XCTAssertEqual(header.streakLine, "打卡 5 天 🔥")
    }

    func testStreakLineIsNilWhenNoStreak() {
        let header = NarrativeHeaderModel.build(
            records: [], samples: [], streak: StreakState()
        )

        XCTAssertNil(header.streakLine, "零打卡不得渲染打卡行")
    }

    func testStreakLineIsNilSafeWithEmptyStore() {
        // 缺省（无注入）路径走 StreakStore —— 空 defaults 的诚实回退是零值。
        let header = NarrativeHeaderModel.build(
            records: [], samples: [],
            streak: StreakStore(defaults: nil).load()
        )

        XCTAssertNil(header.streakLine)
    }

    // MARK: - TimelineViewModel 组装（叙事头 + 本月区）

    func testTimelineViewModelBuildsNarrativeHeaderAndMonthlySection() {
        let now = Date()
        record(size: 1_000, cleanedAt: now)

        let viewModel = TimelineViewModel(persistence: persistence)
        viewModel.refresh(
            environment: NarrativeEnvironment(
                samples: [sample(-8, used: 100_000_000_000, from: now),
                          sample(0, used: 94_000_000_000, from: now)],
                streak: StreakState()
            )
        )

        XCTAssertTrue(viewModel.narrative.headline.contains("回收"))
        XCTAssertTrue(viewModel.narrative.sub.contains("轻 6%"))
        XCTAssertNotNil(viewModel.monthly, "「本月」可展开区需要月报数据模型")
        XCTAssertEqual(viewModel.monthly?.weekly.count, 4)
        XCTAssertEqual(viewModel.events.count, 1)
    }

    func testTimelineViewModelEmptyHistoryStaysHonest() {
        let viewModel = TimelineViewModel(persistence: persistence)
        viewModel.refresh(environment: NarrativeEnvironment(samples: [], streak: StreakState()))

        XCTAssertEqual(viewModel.narrative.headline, "这周还没有清理记录")
        XCTAssertNil(viewModel.narrative.streakLine)
        XCTAssertNotNil(viewModel.monthly)
        XCTAssertTrue(viewModel.events.isEmpty)
    }

    // MARK: - 月报退役（nav.monthlyReport 全残为零）

    func testMonthlyReportNavCaseIsRetired() {
        XCTAssertFalse(AppState.NavigationItem.allCases.map(\.rawValue).contains("monthlyReport"),
                       "P2 T7: nav.monthlyReport case 必须删除")
    }

    func testReportDeepLinkLandsOnHistory() {
        // 月报已并入历史页 —— klaris://report 诚实落到历史（叙事头所在）。
        let state = AppState()
        let coordinator = AppCoordinator(appState: state)

        XCTAssertTrue(coordinator.handleDeepLink(URL(string: "klaris://report")!))
        XCTAssertEqual(state.navigation, .history)
        XCTAssertTrue(coordinator.handleDeepLink(URL(string: "klaris://monthlyreport")!))
        XCTAssertEqual(state.navigation, .history)
    }
}
