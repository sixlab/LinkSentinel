import XCTest
@testable import MonitorCore

final class HistoryTests: XCTestCase {
    func testUpdatingRequestKeepsItsPositionAndOtherRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let store = try HistoryStore(url: url)
        var first = RequestRecord(startedAt: Date(), url: "https://example.com/first", elapsedMilliseconds: 1000, outcome: .timeout, statusCode: nil, detail: "等待中", notification: .sent, phase: .running)
        let sequence = try store.append(first)
        let second = RequestRecord(startedAt: Date(), url: "https://example.com/second", elapsedMilliseconds: 30, outcome: .success, statusCode: 204, detail: "HTTP 204", notification: .notNeeded)
        try store.append(second)
        first.elapsedMilliseconds = 8000
        first.phase = .finished
        try store.update(first, sequence: sequence)
        let reopened = try HistoryStore(url: url)
        XCTAssertEqual(try reopened.count(), 2)
        let records = try reopened.page()
        XCTAssertEqual(records.map(\.id), [second.id, first.id])
        XCTAssertEqual(records.last?.elapsedMilliseconds, 8000)
        XCTAssertEqual(records.last?.notification, .sent)
        XCTAssertEqual(records.last?.phase, .finished)
        XCTAssertThrowsError(try store.update(first, sequence: sequence + 999))
    }

    func testInterruptedRunningRowsAreRecoveredWithoutChangingCompletedHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        for outcome: ProbeOutcome in [.pending, .timeout, .success] {
            try store.append(RequestRecord(startedAt: Date(), url: "https://example.com", elapsedMilliseconds: 1000, outcome: outcome, statusCode: nil, detail: "记录", notification: .notNeeded, phase: outcome == .success ? nil : .running))
        }
        try store.recoverInterruptedRequests()
        try store.recoverInterruptedRequests()
        let records = try store.page()
        XCTAssertEqual(records.map(\.outcome), [.success, .timeout, .cancelled])
        XCTAssertEqual(records.map(\.phase), [nil, .interrupted, .interrupted])
        XCTAssertEqual(records[0].detail, "记录")
        XCTAssertEqual(try store.count(), 3)
    }

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
