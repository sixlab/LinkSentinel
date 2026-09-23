import XCTest
@testable import MonitorCore

final class ProbeTests: XCTestCase {
    private func run(_ path: String, threshold: Int = 1000) async -> ProbeResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let settings = MonitorSettings(url: URL(string: "https://fixture.test/\(path)")!, thresholdMilliseconds: threshold, intervalSeconds: 5)
        return await NetworkProbe(configuration: configuration).run(settings)
    }

    func testSuccessfulRequestDoesNotAlert() async {
        let result = await run("ok")
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.statusCode, 200)
        XCTAssertFalse(result.shouldNotify)
    }

    func testHTTPErrorAlerts() async {
        let result = await run("http-error")
        XCTAssertEqual(result.outcome, .failure)
        XCTAssertEqual(result.statusCode, 503)
        XCTAssertTrue(result.shouldNotify)
    }

    func testNetworkFailureAlerts() async {
        let result = await run("offline")
        XCTAssertEqual(result.outcome, .failure)
        XCTAssertTrue(result.shouldNotify)
    }

    func testSlowRequestFinishesAndRecordsTotalDuration() async {
        let result = await run("delayed-success", threshold: 80)
        XCTAssertEqual(result.outcome, .timeout)
        XCTAssertEqual(result.statusCode, 200)
        XCTAssertGreaterThanOrEqual(result.elapsedMilliseconds, 280)
        XCTAssertTrue(result.shouldNotify)
    }

    func testSlowHTTPErrorRemainsFailureAfterThreshold() async {
        let result = await run("delayed-http-error", threshold: 80)
        XCTAssertEqual(result.outcome, .failure)
        XCTAssertEqual(result.statusCode, 503)
        XCTAssertGreaterThanOrEqual(result.elapsedMilliseconds, 280)
        XCTAssertTrue(result.shouldNotify)
    }

    func testSlowNetworkErrorRemainsFailureAfterThreshold() async {
        let result = await run("delayed-offline", threshold: 80)
        XCTAssertEqual(result.outcome, .failure)
        XCTAssertGreaterThanOrEqual(result.elapsedMilliseconds, 280)
        XCTAssertTrue(result.shouldNotify)
    }

    func testCancellationDoesNotSendAnAlert() async {
        let task = Task { await self.run("slow", threshold: 40) }
        try? await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertFalse(result.shouldNotify)
    }

    func testStreamingResponseWaitsForEntireBody() async {
        let result = await run("stream", threshold: 80)
        XCTAssertEqual(result.outcome, .timeout)
        XCTAssertEqual(result.statusCode, 200)
        XCTAssertGreaterThanOrEqual(result.elapsedMilliseconds, 550)
        XCTAssertTrue(result.shouldNotify)
    }
}

// Only the external HTTP transport is replaced; classification, timing and cancellation are real.
final class FixtureURLProtocol: URLProtocol {
    private let queue = DispatchQueue(label: "LinkSentinel.Tests.transport")
    private var streamTimer: DispatchSourceTimer?
    private var pendingResponse: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        queue.async { [self] in respond() }
    }
    private func respond() {
        switch request.url!.path {
        case "/slow": return
        case "/delayed-success", "/delayed-http-error", "/delayed-offline":
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.request.url!.path == "/delayed-offline" {
                    self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                } else {
                    self.complete(status: self.request.url!.path == "/delayed-http-error" ? 503 : 200)
                }
            }
            pendingResponse = work
            queue.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
        case "/offline":
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case "/stream":
            // 明确类型，避免 MIME 嗅探缓冲首包；正文在 600 毫秒后完整结束。
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/octet-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .milliseconds(30), repeating: .milliseconds(30))
            var chunks = 0
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didLoad: Data("still sending".utf8))
                chunks += 1
                if chunks == 20 {
                    self.streamTimer?.cancel()
                    self.streamTimer = nil
                    self.client?.urlProtocolDidFinishLoading(self)
                }
            }
            streamTimer = timer
            timer.resume()
        default:
            complete(status: request.url!.path == "/http-error" ? 503 : 200)
        }
    }
    private func complete(status: Int) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("fixture".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        queue.async { [self] in
            pendingResponse?.cancel()
            pendingResponse = nil
            streamTimer?.cancel()
            streamTimer = nil
        }
    }
}
