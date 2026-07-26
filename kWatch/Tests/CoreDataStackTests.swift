import XCTest
import CoreData
@testable import kWatch

final class CoreDataStackTests: XCTestCase {
    func testInMemoryHistoryRoundTrips() throws {
        let stack = try CoreDataStack(inMemory: true)
        let record = MetricHistoryRecord(context: stack.viewContext)
        record.timestamp = Date(timeIntervalSince1970: 1)
        record.cpuPercent = 25
        record.memoryPercent = 50
        record.diskPercent = 75
        record.networkReceiveBytesPerSecond = 1_024
        record.networkSendBytesPerSecond = 2_048

        try stack.save()

        let request = NSFetchRequest<MetricHistoryRecord>(entityName: "MetricHistoryRecord")
        let results = try stack.viewContext.fetch(request)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.cpuPercent, 25)
    }

    func testAlertRecordIsPersistable() throws {
        let stack = try CoreDataStack(inMemory: true)
        let alert = AlertRecord(context: stack.viewContext)
        alert.id = UUID()
        alert.kindRaw = "cpu"
        alert.operatorRaw = "above"
        alert.threshold = 80
        alert.isEnabled = true
        alert.cooldownSeconds = 60

        try stack.save()

        let request = NSFetchRequest<AlertRecord>(entityName: "AlertRecord")
        XCTAssertEqual(try stack.viewContext.fetch(request).count, 1)
    }
}
