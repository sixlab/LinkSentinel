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
        task = Task { [weak self] in
            defer { self?.activeTasks[token] = nil }
            // 计数仅属于本轮监控，停止或重启后不会继承旧请求的异常次数。
            var pendingAnomalies = 0
            while !Task.isCancelled {
                guard let self, self.generation == token else { return }
                let tick = ProcessInfo.processInfo.systemUptime
                let date = Date()
                self.isRequestInFlight = true
                let result = await self.probe.run(settings)
                let isCurrent = self.generation == token && !Task.isCancelled
                var detail = result.detail
                var shouldNotify = false
                if isCurrent {
                    if result.shouldNotify {
                        pendingAnomalies += 1
                        detail += " · 本轮连续异常 \(pendingAnomalies)/\(settings.consecutiveAnomalyLimit) 次"
                        if pendingAnomalies == settings.consecutiveAnomalyLimit {
                            shouldNotify = true
                            pendingAnomalies = 0
                        }
                    } else {
                        pendingAnomalies = 0
                    }
                }
                var record = RequestRecord(startedAt: date, url: settings.url.absoluteString, elapsedMilliseconds: result.elapsedMilliseconds, outcome: isCurrent ? result.outcome : .cancelled, statusCode: result.statusCode, detail: isCurrent ? detail : "监控已停止", notification: .notNeeded)
                if isCurrent {
                    self.isRequestInFlight = false
                    switch result.outcome {
                    case .timeout: self.state = .timeout
                    case .failure: self.state = .failure
                    case .success, .cancelled: self.state = .monitoring
                    }
                    self.latestDetail = detail
                    if shouldNotify {
                        record.notification = await self.notifier.send(for: record)
                    }
                }
                self.persist(record)
                guard self.generation == token, !Task.isCancelled else { return }
                let remaining = settings.intervalSeconds - (ProcessInfo.processInfo.systemUptime - tick)
                if remaining > 0 {
                    do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                    catch { return }
                }
            }
        }
        activeTasks[token] = task
    }

    public func stop() {
        generation = nil
        task?.cancel()
        task = nil
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

    private func persist(_ record: RequestRecord) {
        do {
            try store.append(record)
            reloadHistory()
        } catch {
            // Retain the failed record visibly and stop, rather than silently lose future history.
            stop()
            records.insert(record, at: 0)
            storageError = "\(error.localizedDescription) 已停止监控，本次记录尚未保存。"
        }
    }

    private func reloadHistory() {
        do {
            totalRecords = try store.count()
            pageIndex = min(pageIndex, pageCount - 1)
            records = try store.page(limit: pageSize, offset: pageIndex * pageSize)
            storageError = nil
        } catch { storageError = error.localizedDescription }
    }
}
