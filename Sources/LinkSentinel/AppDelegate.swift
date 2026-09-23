import AppKit
import SwiftUI
import Combine
#if SWIFT_PACKAGE
import MonitorCore
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var model: MonitorController!
    private var notifications: NotificationService!
    private let presentation = WindowPresentation()
    private var subscriptions = Set<AnyCancellable>()
    private var monitoringActivity: NSObjectProtocol?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let legacy = UserDefaults(suiteName: "com.local.LinkSentinel") {
            PreferencesMigration.migrate(from: legacy, to: .standard)
        }
        configureMainMenu()
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("LinkSentinel", isDirectory: true)
            let store = try HistoryStore(url: folder.appendingPathComponent("history.sqlite"))
            notifications = NotificationService()
            notifications.onOpen = { [weak self] in self?.showWindow() }
            model = MonitorController(store: store, notifier: notifications)
            configureWindow()
            configureStatusItem()
            showWindow()
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "无法打开链接哨兵"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func configureWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "链接哨兵 · 链接监控"
        window.minSize = NSSize(width: 900, height: 620)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("LinkSentinel.MainWindow")
        window.contentView = NSHostingView(rootView: MonitorView(model: model, notifications: notifications, presentation: presentation))
        window.center()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        model.$state.sink { [weak self] state in self?.updateStatusIcon(state) }.store(in: &subscriptions)
    }

    private func updateStatusIcon(_ state: MonitorState) {
        if state != .stopped, monitoringActivity == nil {
            monitoringActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "定时检查链接并发送异常通知")
        } else if state == .stopped, let monitoringActivity {
            ProcessInfo.processInfo.endActivity(monitoringActivity)
            self.monitoringActivity = nil
        }
        let color: NSColor
        switch state {
        case .stopped: color = .systemGray
        case .monitoring: color = .systemGreen
        case .timeout: color = .systemYellow
        case .failure: color = .systemRed
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3.5, dy: 3.5)).fill()
            return true
        }
        image.isTemplate = false
        statusItem.button?.image = image
        statusItem.button?.toolTip = "链接哨兵 · \(state.rawValue)\n双击打开 · 右键显示菜单"
        statusItem.button?.setAccessibilityLabel("链接哨兵，\(state.rawValue)，双击打开窗口")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showStatusMenu()
        } else if event.clickCount >= 2 {
            showWindow()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        let status = menu.addItem(withTitle: model.state.rawValue, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开监控窗口", action: #selector(showWindow), keyEquivalent: "").target = self
        if model.isRunning {
            menu.addItem(withTitle: "停止监控", action: #selector(stopMonitoring), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出链接哨兵", action: #selector(quit), keyEquivalent: "q").target = self
        // Attach only while tracking; a permanently attached menu consumes double-clicks.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func showWindow() {
        guard window != nil, !isTerminating else { return }
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        // 等 Dock / 菜单栏完成模式切换后再聚焦，避免第一次打开时焦点丢失。
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window.isVisible, !self.isTerminating else { return }
            self.refreshDockIcon()
            NSApp.activate(ignoringOtherApps: true)
            self.window.makeKeyAndOrderFront(nil)
            self.presentation.focusToken = UUID()
        }
        Task { await notifications.refreshPermission() }
    }

    private func refreshDockIcon() {
        // accessory → regular 会创建新的 Dock 图块；切换完成后再设置已解码的图像。
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let source = NSImage(contentsOf: iconURL),
              let pixels = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        NSApp.applicationIconImage = NSImage(cgImage: pixels, size: NSSize(width: 512, height: 512))
        NSApp.dockTile.display()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func stopMonitoring() { model.stop() }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model != nil else { return .terminateNow }
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        Task { @MainActor in
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func configureMainMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "退出链接哨兵", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        main.addItem(edit)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }
}
