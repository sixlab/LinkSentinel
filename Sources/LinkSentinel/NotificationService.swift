import AppKit
import Combine
import UserNotifications
#if SWIFT_PACKAGE
import MonitorCore
#endif

@MainActor
final class NotificationService: NSObject, ObservableObject, AlertSending, UNUserNotificationCenterDelegate {
    @Published private(set) var permissionText = "开启监控时将请求通知权限"
    @Published private(set) var needsSettings = false
    private let center = UNUserNotificationCenter.current()
    var onOpen: (() -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { permissionText = "无法申请通知权限：\(error.localizedDescription)"; return }
        }
        await refreshPermission()
    }

    func refreshPermission() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            needsSettings = settings.alertSetting != .enabled
            permissionText = needsSettings ? "通知横幅未开启，可在系统设置中启用" : "系统通知已授权"
        case .denied:
            needsSettings = true
            permissionText = "通知未授权：异常仍会记录，但无法弹出系统通知"
        case .notDetermined:
            needsSettings = false
            permissionText = "开启监控时将请求通知权限"
        @unknown default:
            needsSettings = true
            permissionText = "请检查系统通知设置"
        }
    }

    func send(for record: RequestRecord) async -> NotificationDelivery {
        let settings = await center.notificationSettings()
        guard !Task.isCancelled else { return .notNeeded }
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else {
            await refreshPermission()
            return .denied
        }
        let content = UNMutableNotificationContent()
        content.title = record.outcome == .timeout ? "链接延迟高" : "链接请求失败"
        content.subtitle = URL(string: record.url)?.host ?? "链接哨兵"
        content.body = "\(record.url)\n响应耗时 \(Int(record.elapsedMilliseconds.rounded())) 毫秒 · \(record.detail)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: record.id.uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
            if Task.isCancelled {
                center.removePendingNotificationRequests(withIdentifiers: [record.id.uuidString])
                center.removeDeliveredNotifications(withIdentifiers: [record.id.uuidString])
            }
            return .sent
        } catch {
            permissionText = "通知发送失败：\(error.localizedDescription)"
            return .failed
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.onOpen?() }
        completionHandler()
    }

    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }
}
