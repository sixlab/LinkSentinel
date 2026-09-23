import XCTest
@testable import MonitorCore

final class HistoryTests: XCTestCase {
    func testHistorySurvivesReopenAndPagesNewestFirstWithoutLosingRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        do {
            let store = try HistoryStore(url: url)
            for index in 0..<5 {
                let record = RequestRecord(startedAt: Date(timeIntervalSince1970: Double(index)), url: "https://example.com/\(index)", elapsedMilliseconds: 25, outcome: .success, statusCode: 200, detail: "HTTP 200", notification: .notNeeded)
                try store.append(record)
            }
        }
        let reopened = try HistoryStore(url: url)
        XCTAssertEqual(try reopened.count(), 5)
        XCTAssertEqual(try reopened.page(limit: 2, offset: 0).map(\.url), ["https://example.com/4", "https://example.com/3"])
        XCTAssertEqual(try reopened.page(limit: 2, offset: 2).map(\.url), ["https://example.com/2", "https://example.com/1"])
        XCTAssertEqual(try reopened.page(limit: 2, offset: 4).count, 1)
    }
}
