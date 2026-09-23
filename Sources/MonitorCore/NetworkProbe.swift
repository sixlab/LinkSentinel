import Foundation

public protocol Probing: Sendable {
    func run(_ settings: MonitorSettings) async -> ProbeResult
}

public struct NetworkProbe: Probing, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
    }

    public func run(_ settings: MonitorSettings) async -> ProbeResult {
        let operation = ProbeOperation(settings: settings, configuration: configuration)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { operation.start($0) }
        } onCancel: {
            operation.cancel()
        }
    }
}

// A single serial queue owns the session, result and continuation.
// Response bytes are discarded as they arrive, so large endpoints cannot fill memory.
private final class ProbeOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "LinkSentinel.probe")
    private let settings: MonitorSettings
    private let configuration: URLSessionConfiguration
    private var continuation: CheckedContinuation<ProbeResult, Never>?
    private var session: URLSession?
    private var started = DispatchTime.now()
    private var responseCode: Int?
    private var finished = false
    private var cancelled = false

    init(settings: MonitorSettings, configuration: URLSessionConfiguration) {
        self.settings = settings
        self.configuration = configuration.copy() as! URLSessionConfiguration
        super.init()
    }

    func start(_ continuation: CheckedContinuation<ProbeResult, Never>) {
        queue.async { [self] in
            self.continuation = continuation
            started = .now()
            guard !cancelled else { finish(.cancelled, "监控已停止"); return }
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.httpCookieStorage = nil
            configuration.waitsForConnectivity = false
            // 告警阈值只用于完成后的耗时判断；传输仍沿用 URLSession 的网络超时设置。
            let delegateQueue = OperationQueue()
            delegateQueue.maxConcurrentOperationCount = 1
            delegateQueue.underlyingQueue = queue
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
            var request = URLRequest(url: settings.url)
            request.httpMethod = "GET"
            request.setValue("LinkSentinel/1.0", forHTTPHeaderField: "User-Agent")
            session?.dataTask(with: request).resume()
        }
    }

    func cancel() {
        queue.async { [self] in
            cancelled = true
            if continuation != nil { finish(.cancelled, "监控已停止") }
        }
    }

    private func finish(_ outcome: ProbeOutcome, _ detail: String) {
        guard !finished, let continuation else { return }
        finished = true
        self.continuation = nil
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        session?.invalidateAndCancel()
        session = nil
        continuation.resume(returning: ProbeResult(elapsedMilliseconds: elapsed, outcome: outcome, statusCode: responseCode, detail: detail))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        responseCode = (response as? HTTPURLResponse)?.statusCode
        completionHandler(finished ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Intentionally do not retain response bodies.
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        if cancelled {
            finish(.cancelled, "监控已停止")
        } else if let error {
            finish(.failure, error.localizedDescription)
        } else if let responseCode, (200..<400).contains(responseCode) {
            if elapsed > Double(settings.thresholdMilliseconds) {
                finish(.timeout, "HTTP \(responseCode) · 请求已完成，超过 \(settings.thresholdMilliseconds) 毫秒阈值")
            } else {
                finish(.success, "HTTP \(responseCode)")
            }
        } else {
            finish(.failure, responseCode.map { "HTTP \($0)" } ?? "服务器没有返回有效的 HTTP 响应")
        }
    }
}
