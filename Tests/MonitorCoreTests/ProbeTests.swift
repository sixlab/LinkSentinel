import XCTest
@testable import MonitorCore

final class ProbeTests: XCTestCase {
    private func run(_ path: String, threshold: Int = 1000) async -> ProbeResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let settings = MonitorSettings(url: URL(string: "https://fixture.test/\(path)")!, thresholdMilliseconds: threshold, intervalSeconds: 5)
        return await NetworkProbe(configuration: configuration).run(settings)
    }

    func testHEADRequestAccepts204WithoutAnAlert() async {
        let result = await run("head-only")
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.statusCode, 204)
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

    func testRedirectIsMeasuredWithoutFollowingItsDestination() async {
        let result = await run("redirect")
        XCTAssertEqual(result.statusCode, 302)
        XCTAssertEqual(result.outcome, .success)
        XCTAssertFalse(result.shouldNotify)
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

    func testHEADResponseFinishesAtHeadersWithoutWaitingForBody() async {
        let result = await run("headers-before-body", threshold: 400)
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.statusCode, 200)
        XCTAssertLessThan(result.elapsedMilliseconds, 400)
        XCTAssertFalse(result.shouldNotify)
    }
}

// Only the external HTTP transport is replaced; classification, timing and cancellation are real.
final class FixtureURLProtocol: URLProtocol {
    private let queue = DispatchQueue(label: "LinkSentinel.Tests.transport")
    private var pendingResponse: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        queue.async { [self] in respond() }
    }
    private func respond() {
        switch request.url!.path {
        case "/redirect":
            let destination = URL(string: "https://fixture.test/redirected-error")!
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": destination.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: destination), redirectResponse: response)
        case "/redirected-error":
            complete(status: 503)
        case "/head-only", "/generate_204":
            complete(status: request.httpMethod == "HEAD" ? 204 : 405)
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
        case "/headers-before-body":
            // 模拟服务器先返回响应头、迟迟不结束传输；HEAD 计时不应等待正文。
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/octet-stream", "Content-Length": "1024"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didLoad: Data(repeating: 0, count: 1024))
                self.client?.urlProtocolDidFinishLoading(self)
            }
            pendingResponse = work
            queue.asyncAfter(deadline: .now() + .milliseconds(700), execute: work)
        default:
            complete(status: request.url!.path == "/http-error" ? 503 : 200)
        }
    }
    private func complete(status: Int) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if request.httpMethod != "HEAD" && status != 204 {
            client?.urlProtocol(self, didLoad: Data("fixture".utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        queue.async { [self] in
            pendingResponse?.cancel()
            pendingResponse = nil
        }
    }
}
