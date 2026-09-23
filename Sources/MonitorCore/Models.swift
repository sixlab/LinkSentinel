import Foundation

public struct MonitorSettings: Codable, Equatable, Sendable {
    public var url: URL
    public var thresholdMilliseconds: Int
    public var intervalSeconds: Double

    public init(url: URL, thresholdMilliseconds: Int, intervalSeconds: Double) {
        self.url = url
        self.thresholdMilliseconds = thresholdMilliseconds
        self.intervalSeconds = intervalSeconds
    }

    public static let defaults = MonitorSettings(url: URL(string: "https://www.gstatic.com/generate_204")!, thresholdMilliseconds: 1000, intervalSeconds: 5)

    public static func validated(url rawURL: String, threshold: String, interval: String) throws -> Self {
        let text = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: { $0.isWhitespace }),
              let components = URLComponents(string: text),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else {
            throw ValidationError.message("请输入完整的 http:// 或 https:// 链接，且不要在链接中包含账号密码。")
        }
        guard let milliseconds = Int(threshold.trimmingCharacters(in: .whitespaces)), (1...3_600_000).contains(milliseconds) else {
            throw ValidationError.message("告警阈值请输入 1～3600000 之间的整数，单位为毫秒。")
        }
        guard let seconds = Double(interval.trimmingCharacters(in: .whitespaces)), seconds.isFinite, (0.1...86400).contains(seconds) else {
            throw ValidationError.message("时间间隔请输入 0.1～86400 之间的数字，单位为秒。")
        }
        return Self(url: url, thresholdMilliseconds: milliseconds, intervalSeconds: seconds)
    }
}

public enum ValidationError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case let .message(text): return text }
    }
}

public enum MonitorState: String, Sendable {
    case stopped = "未开启"
    case monitoring = "监控中"
    case timeout = "延迟高"
    case failure = "失败"
}

public enum ProbeOutcome: String, Codable, Sendable {
    // 保留 timeout 的存储值，以兼容已经保存的请求历史。
    case success, timeout, failure, cancelled
    public var label: String {
        switch self {
        case .success: return "正常"
        case .timeout: return "延迟高"
        case .failure: return "请求失败"
        case .cancelled: return "已取消"
        }
    }
}

public enum NotificationDelivery: String, Codable, Sendable {
    case notNeeded, sent, denied, failed
    public var label: String {
        switch self {
        case .notNeeded: return "否"
        case .sent: return "是 · 已发送"
        case .denied: return "未发送 · 未授权"
        case .failed: return "未发送 · 失败"
        }
    }
}

public struct ProbeResult: Sendable {
    public let elapsedMilliseconds: Double
    public let outcome: ProbeOutcome
    public let statusCode: Int?
    public let detail: String
    public var shouldNotify: Bool { outcome == .timeout || outcome == .failure }

    public init(elapsedMilliseconds: Double, outcome: ProbeOutcome, statusCode: Int? = nil, detail: String) {
        self.elapsedMilliseconds = elapsedMilliseconds
        self.outcome = outcome
        self.statusCode = statusCode
        self.detail = detail
    }
}

public struct RequestRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let url: String
    public let elapsedMilliseconds: Double
    public let outcome: ProbeOutcome
    public let statusCode: Int?
    public let detail: String
    public var notification: NotificationDelivery

    public init(id: UUID = UUID(), startedAt: Date, url: String, elapsedMilliseconds: Double, outcome: ProbeOutcome, statusCode: Int?, detail: String, notification: NotificationDelivery) {
        self.id = id
        self.startedAt = startedAt
        self.url = url
        self.elapsedMilliseconds = elapsedMilliseconds
        self.outcome = outcome
        self.statusCode = statusCode
        self.detail = detail
        self.notification = notification
    }
}
