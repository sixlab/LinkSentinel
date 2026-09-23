import XCTest
@testable import MonitorCore

@MainActor
final class ControllerTests: XCTestCase {
    private func makeController(probe: any Probing) throws -> (MonitorController, URL, String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "LinkSentinel.Tests.\(UUID().uuidString)"
        let model = MonitorController(store: try HistoryStore(url: directory.appendingPathComponent("history.sqlite")), probe: probe, notifier: DeniedNotifier(), defaults: UserDefaults(suiteName: suite)!)
        return (model, directory, suite)
    }

    func testStartsImmediatelyRecoversAndRecordsDeniedNotification() async throws {
        let (model, directory, suite) = try makeController(probe: SequenceProbe())
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        model.intervalText = "0.1"
        model.consecutiveAnomalyText = "1"
        try model.start()
        try await waitUntil { model.totalRecords == 1 }
        XCTAssertEqual(model.state, .timeout)
        XCTAssertEqual(model.records.first?.notification, .denied)
        try await waitUntil { model.totalRecords >= 2 }
        XCTAssertEqual(model.state, .monitoring)
        XCTAssertEqual(model.records.first?.notification, .notNeeded)
        model.stop()
        XCTAssertEqual(model.state, .stopped)
    }

    func testFreshSettingsMonitorThe204EndpointWithHEAD() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let (model, directory, suite) = try makeController(probe: NetworkProbe(configuration: configuration))
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        try model.start()
        try await waitUntil { model.totalRecords == 1 }
        XCTAssertEqual(model.records.first?.url, "https://www.gstatic.com/generate_204")
        XCTAssertEqual(model.records.first?.statusCode, 204)
        XCTAssertEqual(model.records.first?.outcome, .success)
    }

    func testSlowRequestPersistsTotalDurationOnlyAfterCompletion() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let (model, directory, suite) = try makeController(probe: NetworkProbe(configuration: configuration))
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        model.urlText = "https://fixture.test/delayed-success"
        model.thresholdText = "80"
        model.consecutiveAnomalyText = "1"
        try model.start()
        try await waitUntil { model.isRequestInFlight }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(model.isRequestInFlight)
        XCTAssertEqual(model.totalRecords, 0)
        try await waitUntil { model.totalRecords == 1 }
        XCTAssertEqual(model.state, .timeout)
        XCTAssertEqual(model.records.first?.statusCode, 200)
        XCTAssertEqual(model.records.first?.notification, .denied)
        let reopened = try HistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        let record = try XCTUnwrap(reopened.page().first)
        XCTAssertGreaterThanOrEqual(record.elapsedMilliseconds, 280)
        XCTAssertEqual(record.outcome, .timeout)
    }

    func testStopCancelsInFlightRequestAndPreventsLateAlertOrStateChange() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let (model, directory, suite) = try makeController(probe: NetworkProbe(configuration: configuration))
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        model.urlText = "https://fixture.test/slow"
        try model.start()
        try await waitUntil { model.isRequestInFlight }
        model.stop()
        try await waitUntil { model.totalRecords == 1 }
        XCTAssertEqual(model.state, .stopped)
        XCTAssertEqual(model.records.first?.outcome, .cancelled)
        XCTAssertEqual(model.records.first?.notification, .notNeeded)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(model.totalRecords, 1)
    }

    func testHTTPAndNetworkErrorsShowFailureStateAndStillNotify() async throws {
        for path in ["http-error", "offline"] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [FixtureURLProtocol.self]
            let (model, directory, suite) = try makeController(probe: NetworkProbe(configuration: configuration))
            defer {
                model.stop()
                try? FileManager.default.removeItem(at: directory)
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            }
            model.urlText = "https://fixture.test/\(path)"
            model.consecutiveAnomalyText = "1"
            try model.start()
            try await waitUntil { model.totalRecords == 1 }
            XCTAssertEqual(model.state.rawValue, "失败", path)
            XCTAssertTrue(model.isRunning)
            XCTAssertEqual(model.records.first?.outcome, .failure)
            XCTAssertEqual(model.records.first?.notification, .denied)
        }
    }

    func testFailureRecoversToMonitoringAfterSuccessfulRequest() async throws {
        let (model, directory, suite) = try makeController(probe: SequenceProbe(firstOutcome: .failure))
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        model.intervalText = "0.1"
        try model.start()
        try await waitUntil { model.totalRecords == 1 }
        XCTAssertEqual(model.state.rawValue, "失败")
        try await waitUntil { model.totalRecords >= 2 }
        XCTAssertEqual(model.state, .monitoring)
        XCTAssertEqual(model.records.first?.outcome, .success)
        model.stop()
        XCTAssertEqual(model.state, .stopped)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("等待状态变更超时")
    }

    func testDefaultLimitNotifiesEveryThirdMixedAnomaly() async throws {
        let outcomes: [ProbeOutcome] = [.timeout, .failure, .timeout, .failure, .failure, .timeout, .timeout, .failure, .failure]
        let (model, directory, suite) = try makeController(probe: OutcomeSequenceProbe(outcomes))
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        model.intervalText = "0.1"
        try model.start()
        try await waitUntil { model.totalRecords >= 9 }
        model.stop()
        let records = Array(model.records.reversed().prefix(9))
        XCTAssertEqual(records.map(\.notification), [.notNeeded, .notNeeded, .denied, .notNeeded, .notNeeded, .denied, .notNeeded, .notNeeded, .denied])
        XCTAssertEqual(records.map(\.outcome), outcomes)
        let persisted = try HistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        XCTAssertEqual(try persisted.page().filter { $0.notification == .denied }.count, 3)
    }

    func testSuccessClearsPendingAnomalies() async throws {
        let outcomes: [ProbeOutcome] = [.failure, .timeout, .success, .failure, .timeout, .failure]
        let (model, directory, suite) = try makeController(probe: OutcomeSequenceProbe(outcomes))
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        model.intervalText = "0.1"
        try model.start()
        try await waitUntil { model.totalRecords >= 6 }
        model.stop()
        XCTAssertEqual(Array(model.records.reversed().prefix(6)).map(\.notification), [.notNeeded, .notNeeded, .notNeeded, .notNeeded, .notNeeded, .denied])
    }

    func testRestartClearsPendingAnomalies() async throws {
        let (model, directory, suite) = try makeController(probe: OutcomeSequenceProbe(Array(repeating: .failure, count: 5)))
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        model.intervalText = "0.1"
        try model.start()
        try await waitUntil { model.totalRecords >= 2 }
        model.stop()
        try model.start()
        try await waitUntil { model.totalRecords >= 5 }
        model.stop()
        XCTAssertEqual(Array(model.records.reversed().prefix(5)).map(\.notification), [.notNeeded, .notNeeded, .notNeeded, .notNeeded, .denied])
    }

    func testCustomLimitPersistsAndControlsNotificationCadence() async throws {
        let (model, directory, suite) = try makeController(probe: OutcomeSequenceProbe(Array(repeating: .failure, count: 4)))
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        model.intervalText = "0.1"
        model.consecutiveAnomalyText = "2"
        try model.start()
        try await waitUntil { model.totalRecords >= 4 }
        await model.shutdown()
        XCTAssertEqual(Array(model.records.reversed().prefix(4)).map(\.notification), [.notNeeded, .denied, .notNeeded, .denied])
        let restored = MonitorController(store: try HistoryStore(url: directory.appendingPathComponent("history.sqlite")), probe: SequenceProbe(), notifier: DeniedNotifier(), defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restored.consecutiveAnomalyText, "2")
    }

    func testResetRestoresAnomalyLimitAndPreservesHistory() async throws {
        let (model, directory, suite) = try makeController(probe: SequenceProbe())
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        model.consecutiveAnomalyText = "8"
        try model.start()
        try await waitUntil { model.totalRecords == 1 }
        model.stop()
        model.resetSettings()
        XCTAssertEqual(model.consecutiveAnomalyText, "3")
        XCTAssertEqual(model.totalRecords, 1)
        let restored = MonitorController(store: try HistoryStore(url: directory.appendingPathComponent("history.sqlite")), probe: SequenceProbe(), notifier: DeniedNotifier(), defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restored.consecutiveAnomalyText, "3")
        XCTAssertEqual(restored.totalRecords, 1)
    }

    func testInvalidAnomalyLimitDoesNotStartOrOverwriteSavedSettings() throws {
        let (model, directory, suite) = try makeController(probe: SequenceProbe())
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        model.consecutiveAnomalyText = "0"
        XCTAssertThrowsError(try model.start())
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.totalRecords, 0)
        XCTAssertNil(UserDefaults(suiteName: suite)?.data(forKey: "monitor.settings"))
    }

    func testRapidRestartIgnoresOldRequestCompletion() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let (model, directory, suite) = try makeController(probe: NetworkProbe(configuration: configuration))
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        model.urlText = "https://fixture.test/slow"
        try model.start()
        try await waitUntil { model.isRequestInFlight }
        model.stop()
        model.urlText = "https://fixture.test/ok"
        try model.start()
        try await waitUntil { model.totalRecords == 2 }
        XCTAssertEqual(model.state, .monitoring)
        XCTAssertEqual(model.records.filter { $0.outcome == .success }.count, 1)
        XCTAssertEqual(model.records.filter { $0.outcome == .cancelled }.count, 1)
        XCTAssertTrue(model.records.allSatisfy { $0.notification == .notNeeded })
    }

    func testShutdownWaitsForCancelledRequestToBeWrittenBeforeReturning() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let (model, directory, suite) = try makeController(probe: NetworkProbe(configuration: configuration))
        defer {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        model.urlText = "https://fixture.test/slow"
        try model.start()
        try await waitUntil { model.isRequestInFlight }
        await model.shutdown()
        let reopened = try HistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        XCTAssertEqual(try reopened.count(), 1)
        XCTAssertEqual(try reopened.page().first?.outcome, .cancelled)
        XCTAssertEqual(try reopened.page().first?.notification, .notNeeded)
        XCTAssertThrowsError(try model.start(), "退出途中不得重新开启监控")
    }
}

private actor SequenceProbe: Probing {
    private var count = 0
    private let firstOutcome: ProbeOutcome
    init(firstOutcome: ProbeOutcome = .timeout) { self.firstOutcome = firstOutcome }
    func run(_ settings: MonitorSettings) async -> ProbeResult {
        count += 1
        return count == 1
            ? ProbeResult(elapsedMilliseconds: 1000, outcome: firstOutcome, detail: firstOutcome.label)
            : ProbeResult(elapsedMilliseconds: 5, outcome: .success, statusCode: 200, detail: "HTTP 200")
    }
}

private actor OutcomeSequenceProbe: Probing {
    private var outcomes: [ProbeOutcome]
    init(_ outcomes: [ProbeOutcome]) { self.outcomes = outcomes }
    func run(_ settings: MonitorSettings) async -> ProbeResult {
        let outcome = outcomes.isEmpty ? .success : outcomes.removeFirst()
        return ProbeResult(elapsedMilliseconds: outcome == .timeout ? 1500 : 5, outcome: outcome, statusCode: outcome == .failure ? nil : 204, detail: outcome.label)
    }
}

@MainActor
private struct DeniedNotifier: AlertSending {
    func send(for record: RequestRecord) async -> NotificationDelivery { .denied }
}
