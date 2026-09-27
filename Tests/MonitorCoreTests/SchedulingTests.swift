import XCTest
@testable import MonitorCore

@MainActor
final class SchedulingTests: XCTestCase {
    func testBlockedUIThreadDoesNotTurnCompletedResponsesIntoTimeouts() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QuickResponseURLProtocol.self]
        // 让实际网络完成后的交付也经过 MainActor，稳定覆盖界面卡顿导致交付晚于阈值。
        for _ in 0..<3 {
            try await withController(probe: DeferredDeliveryProbe(base: NetworkProbe(configuration: configuration))) { model, notifier, _ in
                model.thresholdText = "40"
                model.consecutiveAnomalyText = "1"
                try model.start()
                try await Task.sleep(nanoseconds: 5_000_000)
                blockCurrentThread(for: 0.1)
                try await Task.sleep(nanoseconds: 80_000_000)
                let record = try XCTUnwrap(model.records.first)
                XCTAssertEqual(record.phase, .finished)
                XCTAssertLessThan(record.elapsedMilliseconds, 40)
                XCTAssertEqual(record.outcome, .success)
                XCTAssertTrue(notifier.records.isEmpty, "界面处理延迟不能被计为网络延迟")
            }
        }
    }

    func testStartsOverlapAndNotifiesAtDeadlineBeforeResponses() async throws {
        let probe = TimedProbe(delays: [1.5, 1.5, 1.5], outcomes: [.timeout, .timeout, .timeout])
        try await withController(probe: probe) { model, notifier, _ in
            model.intervalText = "0.1"
            model.thresholdText = "30"
            model.consecutiveAnomalyText = "2"
            try model.start()
            try await Task.sleep(nanoseconds: 280_000_000)
            let starts = await probe.starts
            XCTAssertGreaterThanOrEqual(starts.count, 3, "前面的请求未完成时仍应发起新请求")
            if starts.count >= 3 {
                XCTAssertLessThan(starts[1] - starts[0], 0.19)
                XCTAssertLessThan(starts[2] - starts[0], 0.29)
            }
            XCTAssertEqual(notifier.records.count, 1, "第二次阈值到达时立即通知，不等 1.5 秒的响应")
            XCTAssertEqual(model.records.filter { $0.outcome == .timeout }.count, 3)
        }
    }

    func testDeadlineRecordIsUpdatedWithoutDuplicateCountOrNotification() async throws {
        let probe = TimedProbe(delays: [0.3], outcomes: [.timeout])
        try await withController(probe: probe) { model, notifier, store in
            model.thresholdText = "40"
            model.consecutiveAnomalyText = "1"
            try model.start()
            try await Task.sleep(nanoseconds: 120_000_000)
            XCTAssertEqual(model.records.first?.outcome, .timeout)
            XCTAssertEqual(notifier.records.count, 1)
            let earlyID = model.records.first?.id
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(model.records.first?.id, earlyID)
            XCTAssertGreaterThanOrEqual(model.records.first?.elapsedMilliseconds ?? 0, 280)
            XCTAssertEqual(try store.count(), 1)
            XCTAssertEqual(notifier.records.count, 1)
        }
    }

    func testDirectFailureNotifiesBeforeThresholdAndIsNotCountedAgain() async throws {
        try await withController(probe: TimedProbe(delays: [0.005], outcomes: [.failure])) { model, notifier, _ in
            model.thresholdText = "200"
            model.consecutiveAnomalyText = "1"
            try model.start()
            try await Task.sleep(nanoseconds: 70_000_000)
            XCTAssertEqual(model.records.first?.outcome, .failure)
            XCTAssertEqual(notifier.records.count, 1)
            try await Task.sleep(nanoseconds: 220_000_000)
            XCTAssertEqual(notifier.records.count, 1)
        }
    }

    func testLateFailureDoesNotOverwriteNewerSuccessOrCountAgain() async throws {
        try await withController(probe: TimedProbe(delays: [0.35, 0.005], outcomes: [.failure, .success])) { model, notifier, _ in
            model.intervalText = "0.1"
            model.thresholdText = "30"
            model.consecutiveAnomalyText = "2"
            try model.start()
            try await Task.sleep(nanoseconds: 390_000_000)
            XCTAssertEqual(model.state, .monitoring)
            XCTAssertEqual(model.records.last?.outcome, .failure)
            XCTAssertGreaterThanOrEqual(model.records.last?.elapsedMilliseconds ?? 0, 330)
            XCTAssertTrue(notifier.records.isEmpty)
        }
    }

    func testFailuresAreCountedWhenJudgedEvenIfOlderRequestIsPending() async throws {
        try await withController(probe: TimedProbe(delays: [1.5, 0.005], outcomes: [.failure, .failure])) { model, notifier, _ in
            model.intervalText = "0.1"
            model.thresholdText = "1000"
            model.consecutiveAnomalyText = "2"
            try model.start()
            try await Task.sleep(nanoseconds: 260_000_000)
            XCTAssertEqual(model.records.last?.outcome, .pending)
            XCTAssertEqual(notifier.records.count, 1)
            XCTAssertEqual(notifier.records.first?.id, model.records.first?.id)
        }
    }

    func testSlowNotificationDoesNotDelayLaunchesOrOverwriteFinalDuration() async throws {
        let probe = TimedProbe(delays: [0.22, 0.005], outcomes: [.timeout, .success])
        try await withController(probe: probe, notifier: RecordingNotifier(delay: 0.3)) { model, notifier, _ in
            model.intervalText = "0.1"
            model.thresholdText = "30"
            model.consecutiveAnomalyText = "1"
            try model.start()
            try await Task.sleep(nanoseconds: 390_000_000)
            let starts = await probe.starts
            XCTAssertGreaterThanOrEqual(starts.count, 4)
            let first = try XCTUnwrap(model.records.last)
            XCTAssertEqual(first.phase, .finished)
            XCTAssertGreaterThanOrEqual(first.elapsedMilliseconds, 200)
            XCTAssertEqual(first.notification, .sent)
            XCTAssertEqual(notifier.records.count, 1)
        }
    }

    func testStopCancelsAllOverlappingRequestsAndPreventsDeadlineAlerts() async throws {
        let probe = TimedProbe(delays: [1.5], outcomes: [.timeout])
        try await withController(probe: probe) { model, notifier, store in
            model.intervalText = "0.1"
            model.thresholdText = "250"
            model.consecutiveAnomalyText = "1"
            try model.start()
            try await Task.sleep(nanoseconds: 160_000_000)
            await model.shutdown()
            XCTAssertEqual(model.totalRecords, 2)
            XCTAssertTrue(model.records.allSatisfy { $0.phase == .finished && $0.outcome == .cancelled })
            XCTAssertFalse(model.isRequestInFlight)
            try await Task.sleep(nanoseconds: 240_000_000)
            XCTAssertTrue(notifier.records.isEmpty)
            XCTAssertEqual(try store.count(), 2)
            XCTAssertEqual(model.state, .stopped)
        }
    }

    private func withController(probe: any Probing, notifier suppliedNotifier: RecordingNotifier? = nil, body: (MonitorController, RecordingNotifier, HistoryStore) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "LinkSentinel.SchedulingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = try HistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        let notifier = suppliedNotifier ?? RecordingNotifier()
        let model = MonitorController(store: store, probe: probe, notifier: notifier, defaults: defaults)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        do { try await body(model, notifier, store) }
        catch { await model.shutdown(); throw error }
        await model.shutdown()
    }
}

private func blockCurrentThread(for duration: TimeInterval) {
    Thread.sleep(forTimeInterval: duration)
}

private struct DeferredDeliveryProbe: Probing {
    let base: NetworkProbe
    func run(_ settings: MonitorSettings, onThreshold: @escaping @Sendable (Double) -> Void) async -> ProbeResult {
        let result = await base.run(settings, onThreshold: onThreshold)
        await MainActor.run {}
        try? await Task.sleep(nanoseconds: 20_000_000)
        return result
    }
}

private final class QuickResponseURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private actor TimedProbe: Probing {
    let delays: [Double]
    let outcomes: [ProbeOutcome]
    private(set) var starts: [Double] = []
    init(delays: [Double], outcomes: [ProbeOutcome]) {
        self.delays = delays
        self.outcomes = outcomes
    }
    func run(_ settings: MonitorSettings, onThreshold: @escaping @Sendable (Double) -> Void) async -> ProbeResult {
        let index = starts.count
        let started = ProcessInfo.processInfo.systemUptime
        starts.append(started)
        let delay = delays[min(index, delays.count - 1)]
        var outcome = outcomes[min(index, outcomes.count - 1)]
        do {
            let threshold = Double(settings.thresholdMilliseconds) / 1000
            if delay >= threshold {
                try await Task.sleep(nanoseconds: UInt64(threshold * 1_000_000_000))
                try Task.checkCancellation()
                onThreshold((ProcessInfo.processInfo.systemUptime - started) * 1000)
                try await Task.sleep(nanoseconds: UInt64((delay - threshold) * 1_000_000_000))
            } else {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        catch { outcome = .cancelled }
        return ProbeResult(elapsedMilliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1000, outcome: outcome, statusCode: outcome == .failure ? nil : 204, detail: outcome.label)
    }
}

@MainActor
private final class RecordingNotifier: AlertSending {
    var records: [RequestRecord] = []
    let delay: Double
    init(delay: Double = 0) { self.delay = delay }
    func send(for record: RequestRecord) async -> NotificationDelivery {
        if delay > 0 {
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return .notNeeded }
        }
        records.append(record)
        return .sent
    }
}
