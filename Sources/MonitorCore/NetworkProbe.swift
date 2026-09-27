import Foundation

public protocol Probing: Sendable {
    // 在网络执行上下文中判定阈值，不能把结果交付到界面的延迟计入网络耗时。
    func run(_ settings: MonitorSettings, onThreshold: @escaping @Sendable (Double) -> Void) async -> ProbeResult
}

public extension Probing {
    func run(_ settings: MonitorSettings) async -> ProbeResult {
        await run(settings, onThreshold: { _ in })
    }
}

public struct NetworkProbe: Probing, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
    }

    public func run(_ settings: MonitorSettings, onThreshold: @escaping @Sendable (Double) -> Void) async -> ProbeResult {
        let operation = ProbeOperation(settings: settings, configuration: configuration, onThreshold: onThreshold)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { operation.start($0) }
        } onCancel: {
            operation.cancel()
        }
    }
}

// A single serial queue owns the session, result and continuation.
// A HEAD probe finishes as soon as response headers arrive, without reading a body.
private final class ProbeOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "LinkSentinel.probe")
    private let settings: MonitorSettings
    private let configuration: URLSessionConfiguration
    private let onThreshold: @Sendable (Double) -> Void
    private var deadlineWork: DispatchWorkItem?
    private var continuation: CheckedContinuation<ProbeResult, Never>?
    private var session: URLSession?
    private var started = DispatchTime.now()
    private var responseCode: Int?
    private var finished = false
    private var cancelled = false

    init(settings: MonitorSettings, configuration: URLSessionConfiguration, onThreshold: @escaping @Sendable (Double) -> Void) {
        self.settings = settings
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.onThreshold = onThreshold
        super.init()
    }

    func start(_ continuation: CheckedContinuation<ProbeResult, Never>) {
        queue.async { [self] in
            self.continuation = continuation
            started = .now()
            guard !cancelled else { finish(.cancelled, "监控已停止"); return }
            // 阈值和完成回调使用同一队列仲裁；阈值只发事件，不取消请求。
            let deadline = DispatchWorkItem { [weak self] in
                guard let self, !self.finished, !self.cancelled else { return }
                self.onThreshold(self.elapsedMilliseconds)
            }
            deadlineWork = deadline
            queue.asyncAfter(deadline: started + .milliseconds(settings.thresholdMilliseconds), execute: deadline)
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.httpCookieStorage = nil
            configuration.waitsForConnectivity = false
            let delegateQueue = OperationQueue()
            delegateQueue.maxConcurrentOperationCount = 1
            delegateQueue.underlyingQueue = queue
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
            var request = URLRequest(url: settings.url)
            request.httpMethod = "HEAD"
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
        deadlineWork?.cancel()
        deadlineWork = nil
        self.continuation = nil
        let elapsed = elapsedMilliseconds
        session?.invalidateAndCancel()
        session = nil
        continuation.resume(returning: ProbeResult(elapsedMilliseconds: elapsed, outcome: outcome, statusCode: responseCode, detail: detail))
    }

    private var elapsedMilliseconds: Double {
        Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !finished else { completionHandler(.cancel); return }
        responseCode = (response as? HTTPURLResponse)?.statusCode
        // HEAD 在收到响应头时已经完成；不读取服务器可能误发的正文。
        completionHandler(.cancel)
        finishResponse()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // 与 Mihomo 普通 URLTest 一致，记录当前地址的响应，不继续请求跳转目标。
        completionHandler(nil)
        guard !finished else { return }
        responseCode = response.statusCode
        finishResponse()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Intentionally do not retain response bodies.
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        if cancelled {
            finish(.cancelled, "监控已停止")
        } else if let error {
            finish(.failure, error.localizedDescription)
        } else {
            finish(.failure, "服务器没有返回有效的 HTTP 响应")
        }
    }

    private func finishResponse() {
        if cancelled {
            finish(.cancelled, "监控已停止")
        } else if let responseCode, (200..<400).contains(responseCode) {
            if elapsedMilliseconds >= Double(settings.thresholdMilliseconds) {
                finish(.timeout, "HEAD · HTTP \(responseCode) · 延迟高，超过 \(settings.thresholdMilliseconds) 毫秒阈值")
            } else {
                finish(.success, "HEAD · HTTP \(responseCode)")
            }
        } else {
            finish(.failure, responseCode.map { "HEAD · HTTP \($0)" } ?? "服务器没有返回有效的 HTTP 响应")
        }
    }
}
