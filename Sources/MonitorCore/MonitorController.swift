import Foundation
import Combine

@MainActor
public protocol AlertSending {
    func send(for record: RequestRecord) async -> NotificationDelivery
}

@MainActor
public final class MonitorController: ObservableObject {
    @Published public var urlText: String
    @Published public var thresholdText: String
    @Published public var intervalText: String
    @Published public var consecutiveAnomalyText: String
    @Published public private(set) var state: MonitorState = .stopped
    @Published public private(set) var isRequestInFlight = false
    @Published public private(set) var records: [RequestRecord] = []
    @Published public private(set) var totalRecords = 0
    @Published public private(set) var pageIndex = 0
    @Published public private(set) var latestDetail = "设置链接与时间，点击开启开始监控。"
    @Published public private(set) var storageError: String?

    public let pageSize = 100
    public var isRunning: Bool { state != .stopped }
    public var pageCount: Int { max(1, (totalRecords + pageSize - 1) / pageSize) }

    private let store: HistoryStore
    private let probe: any Probing
    private let notifier: any AlertSending
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var generation: UUID?
    private var requests: [UUID: ActiveRequest] = [:]
    private var pendingAnomalies = 0
    private var latestJudgedID: UUID?
    private var writeFailure: String?
    private var isShuttingDown = false

    public init(store: HistoryStore, probe: any Probing = NetworkProbe(), notifier: any AlertSending, defaults: UserDefaults = .standard) {
        self.store = store
        self.probe = probe
        self.notifier = notifier
        self.defaults = defaults
        let saved = defaults.data(forKey: "monitor.settings").flatMap { try? JSONDecoder().decode(MonitorSettings.self, from: $0) }
        let settings = saved.flatMap {
            try? MonitorSettings.validated(url: $0.url.absoluteString, threshold: String($0.thresholdMilliseconds), interval: String($0.intervalSeconds), consecutiveAnomalies: String($0.consecutiveAnomalyLimit))
        } ?? .defaults
        urlText = settings.url.absoluteString
        thresholdText = String(settings.thresholdMilliseconds)
        intervalText = settings.intervalSeconds.rounded() == settings.intervalSeconds && settings.intervalSeconds.isFinite && settings.intervalSeconds <= 86400
            ? String(Int(settings.intervalSeconds)) : String(settings.intervalSeconds)
        consecutiveAnomalyText = String(settings.consecutiveAnomalyLimit)
        do { try store.recoverInterruptedRequests() }
        catch { writeFailure = error.localizedDescription }
        reloadHistory()
    }

    public func resetSettings() {
        guard !isRunning, !isShuttingDown else { return }
        let settings = MonitorSettings.defaults
        urlText = settings.url.absoluteString
        thresholdText = String(settings.thresholdMilliseconds)
        intervalText = String(Int(settings.intervalSeconds))
        consecutiveAnomalyText = String(settings.consecutiveAnomalyLimit)
        defaults.removeObject(forKey: "monitor.settings")
        latestDetail = "已恢复默认设置，点击开启开始监控。"
    }

    public func start() throws {
        guard !isShuttingDown else { throw ValidationError.message("应用正在退出，请稍候。") }
        guard !isRunning else { return }
        let settings = try MonitorSettings.validated(url: urlText, threshold: thresholdText, interval: intervalText, consecutiveAnomalies: consecutiveAnomalyText)
        urlText = settings.url.absoluteString
        defaults.set(try JSONEncoder().encode(settings), forKey: "monitor.settings")
        let token = UUID()
        generation = token
        state = .monitoring
        latestDetail = "正在发起首次请求…"
        pendingAnomalies = 0
        latestJudgedID = nil
        writeFailure = nil
        task = Task { [weak self] in
            let clock = ContinuousClock()
            var nextLaunch = clock.now
            while !Task.isCancelled {
                guard let self, self.generation == token else { return }
                self.launch(settings, token: token)
                guard self.generation == token else { return }
                nextLaunch += .seconds(settings.intervalSeconds)
                // 睡眠唤醒或主线程长时间受阻时只恢复一次，不补发积压请求。
                if nextLaunch <= clock.now { nextLaunch = clock.now + .seconds(settings.intervalSeconds) }
                do { try await clock.sleep(until: nextLaunch) }
                catch { return }
            }
        }
    }

    private func launch(_ settings: MonitorSettings, token: UUID) {
        let record = RequestRecord(startedAt: Date(), url: settings.url.absoluteString, elapsedMilliseconds: 0,
                                   outcome: .pending, statusCode: nil, detail: "请求进行中…", notification: .notNeeded, phase: .running)
        let sequence: Int64
        do { sequence = try store.append(record) }
        catch { storageFailed(error, record: record); return }
        let request = ActiveRequest(record: record, sequence: sequence, settings: settings, token: token)
        requests[record.id] = request
        isRequestInFlight = true
        reloadHistory()
        let worker = Task { [weak self, probe] in
            // 网络队列负责仲裁，流保证阈值事件先于最终结果处理。
            let (thresholds, continuation) = AsyncStream<Double>.makeStream()
            let operation = Task.detached {
                let result = await probe.run(settings, onThreshold: { continuation.yield($0) })
                continuation.finish()
                return result
            }
            let result = await withTaskCancellationHandler {
                for await elapsed in thresholds {
                    self?.thresholdReached(request, elapsed: elapsed)
                }
                return await operation.value
            } onCancel: {
                operation.cancel()
            }
            guard let self else { return }
            defer { self.activeTasks[record.id] = nil }
            self.finish(request, result: result, cancelled: Task.isCancelled)
        }
        activeTasks[record.id] = worker
    }

    private func thresholdReached(_ request: ActiveRequest, elapsed: Double) {
        guard generation == request.token, !Task.isCancelled,
              requests[request.record.id] != nil, !request.wasJudged else { return }
        request.record.elapsedMilliseconds = elapsed
        request.record.outcome = .timeout
        request.record.detail = "已达到 \(request.settings.thresholdMilliseconds) 毫秒阈值，仍在等待响应"
        let notify = judge(request)
        save(request)
        if notify { sendNotification(request) }
    }

    // 按判定事件的先后更新连续计数。迟到的响应只更新原记录，不再次计数。
    private func judge(_ request: ActiveRequest) -> Bool {
        request.wasJudged = true
        var notify = false
        if request.record.outcome == .timeout || request.record.outcome == .failure {
            pendingAnomalies += 1
            request.countDetail = " · 本轮连续异常 \(pendingAnomalies)/\(request.settings.consecutiveAnomalyLimit) 次"
            request.record.detail += request.countDetail
            if pendingAnomalies == request.settings.consecutiveAnomalyLimit {
                pendingAnomalies = 0
                notify = true
            }
        } else {
            pendingAnomalies = 0
        }
        latestJudgedID = request.record.id
        showState(request.record)
        return notify
    }

    private func finish(_ request: ActiveRequest, result: ProbeResult, cancelled: Bool) {
        request.record.elapsedMilliseconds = result.elapsedMilliseconds
        request.record.statusCode = result.statusCode
        request.record.phase = .finished
        let isCurrent = generation == request.token && !cancelled
        var notify = false
        if isCurrent {
            // 已在阈值时标记的延迟高不会被迟到的成功响应改回正常。
            request.record.outcome = request.wasJudged && result.outcome == .success ? .timeout : result.outcome
            request.record.detail = result.detail + request.countDetail
            if !request.wasJudged {
                notify = judge(request)
            } else if latestJudgedID == request.record.id {
                showState(request.record)
            }
        } else {
            request.record.outcome = .cancelled
            request.record.detail = "监控已停止" + request.countDetail
        }
        requests[request.record.id] = nil
        isRequestInFlight = requests.values.contains { $0.token == generation }
        save(request)
        if notify { sendNotification(request) }
    }

    private func showState(_ record: RequestRecord) {
        switch record.outcome {
        case .timeout: state = .timeout
        case .failure: state = .failure
        case .pending, .success, .cancelled: state = .monitoring
        }
        latestDetail = record.detail
    }

    private func sendNotification(_ request: ActiveRequest) {
        guard generation == request.token else { return }
        let id = UUID()
        let notificationRecord = request.record
        activeTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.activeTasks[id] = nil }
            guard self.generation == request.token, !Task.isCancelled else { return }
            let delivery = await self.notifier.send(for: notificationRecord)
            // 与最终响应共享同一条记录，防止较晚的通知结果覆盖完整耗时。
            request.record.notification = delivery
            self.save(request)
        }
    }

    public func stop() {
        generation = nil
        task?.cancel()
        task = nil
        pendingAnomalies = 0
        latestJudgedID = nil
        for task in activeTasks.values { task.cancel() }
        isRequestInFlight = false
        state = .stopped
        latestDetail = "监控已停止，历史记录已保留。"
    }

    public func shutdown() async {
        isShuttingDown = true
        stop()
        // Include previous generations still finishing cancellation or notification delivery.
        let pending = Array(activeTasks.values)
        for task in pending { task.cancel() }
        for task in pending { await task.value }
    }

    public func previousPage() {
        guard pageIndex > 0 else { return }
        pageIndex -= 1
        reloadHistory()
    }

    public func nextPage() {
        guard pageIndex + 1 < pageCount else { return }
        pageIndex += 1
        reloadHistory()
    }

    private func save(_ request: ActiveRequest) {
        do {
            try store.update(request.record, sequence: request.sequence)
            reloadHistory()
        } catch { storageFailed(error, record: request.record) }
    }

    private func storageFailed(_ error: Error, record: RequestRecord) {
        stop()
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
        else { records.insert(record, at: 0) }
        writeFailure = "\(error.localizedDescription) 已停止监控，本次记录尚未保存。"
        storageError = writeFailure
    }

    private func reloadHistory() {
        do {
            totalRecords = try store.count()
            pageIndex = min(pageIndex, pageCount - 1)
            records = try store.page(limit: pageSize, offset: pageIndex * pageSize)
            storageError = writeFailure
        } catch { storageError = error.localizedDescription }
    }
}

// 由控制器的主 actor 管理；网络完成、阈值和通知回调共同更新同一条记录。
private final class ActiveRequest {
    var record: RequestRecord
    let sequence: Int64
    let settings: MonitorSettings
    let token: UUID
    var wasJudged = false
    var countDetail = ""

    init(record: RequestRecord, sequence: Int64, settings: MonitorSettings, token: UUID) {
        self.record = record
        self.sequence = sequence
        self.settings = settings
        self.token = token
    }
}
