import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MonitorCore
#endif

@MainActor
final class WindowPresentation: ObservableObject {
    @Published var focusToken = UUID()
}

extension MonitorState {
    var color: Color {
        switch self {
        case .stopped: return .gray
        case .monitoring: return .green
        case .timeout: return .yellow
        case .failure: return .red
        }
    }
}

struct MonitorView: View {
    @ObservedObject var model: MonitorController
    @ObservedObject var notifications: NotificationService
    @ObservedObject var presentation: WindowPresentation
    @State private var errorMessage: String?
    @State private var isStarting = false
    @State private var selectedRecordIDs = Set<RequestRecord.ID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("监控链接").font(.headline)
                    URLInput(text: $model.urlText, focusToken: presentation.focusToken, isMonitoring: model.isRunning || isStarting)
                        .frame(height: 28)
                }
                HStack(alignment: .bottom, spacing: 20) {
                    numberField("告警阈值", unit: "毫秒", text: $model.thresholdText)
                    numberField("时间间隔", unit: "秒", text: $model.intervalText)
                    Spacer()
                    Button {
                        model.resetSettings()
                        presentation.focusToken = UUID()
                    } label: {
                        Label("重置", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.isRunning || isStarting)
                    .help("恢复默认链接、告警阈值和时间间隔")
                    .accessibilityIdentifier("resetSettings")
                    Button(action: toggle) {
                        Label(isStarting ? "准备中…" : model.isRunning ? "停止监控" : "开启监控", systemImage: model.isRunning ? "stop.fill" : "play.fill")
                            .frame(width: 112)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(model.isRunning ? .red : .accentColor)
                    .disabled(isStarting)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("toggleMonitoring")
                }
                Text("使用 HEAD 请求测量响应延迟，超过阈值时通知。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Image(systemName: notifications.needsSettings ? "bell.slash" : "bell")
                    Text(notifications.permissionText)
                    if notifications.needsSettings {
                        Button("打开系统设置", action: notifications.openSettings).buttonStyle(.link)
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()
            HStack(spacing: 8) {
                Circle().fill(model.state.color).frame(width: 9, height: 9)
                Text(model.state.rawValue).fontWeight(.semibold)
                if model.isRequestInFlight { ProgressView().controlSize(.mini) }
                Text(model.latestDetail).foregroundStyle(.secondary).lineLimit(1).help(model.latestDetail)
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            if let storageError = model.storageError {
                Text(storageError).font(.caption).foregroundStyle(.red).padding(.horizontal, 24).padding(.bottom, 12)
            }

            HStack {
                Text("请求记录").font(.headline)
                Spacer()
                Text("共 \(model.totalRecords) 条 · 保存在本机").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.bottom, 10)

            historyTable
                .overlay {
                    if model.records.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "waveform.path.ecg").font(.system(size: 32, weight: .light))
                            Text("还没有请求记录").font(.headline)
                            Text("开启监控后，每次请求都会显示在这里。")
                                .font(.callout)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    }
                }
            footer
        }
        .frame(minWidth: 900, minHeight: 600)
        .alert("无法开启监控", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 46, height: 46)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("链接哨兵").font(.system(size: 23, weight: .semibold, design: .rounded))
                Text("链接状态，随时掌握").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text("菜单栏监控工具").font(.caption).foregroundStyle(.secondary)
        }.padding(24)
    }

    private func numberField(_ title: String, unit: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            HStack(spacing: 8) {
                TextField(title, text: text)
                    .labelsHidden().textFieldStyle(.roundedBorder)
                    .frame(width: 116)
                    .disabled(model.isRunning || isStarting)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }

    private var historyTable: some View {
        Table(model.records, selection: $selectedRecordIDs) {
            TableColumn("请求开始时间") { record in
                Text(record.startedAt, format: .dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                    .monospacedDigit().help(record.startedAt.formatted(date: .complete, time: .complete))
            }.width(min: 140, ideal: 150, max: 170)
            TableColumn("链接") { record in
                Text(record.url).lineLimit(1).truncationMode(.middle).help(record.url)
            }.width(min: 170, ideal: 280)
            TableColumn("响应耗时") { record in
                Text("\(record.elapsedMilliseconds.formatted(.number.precision(.fractionLength(0)))) ms")
                    .monospacedDigit()
            }.width(82)
            TableColumn("结果") { record in
                Text(record.outcome.label)
                    .foregroundStyle(record.outcome == .failure ? Color.red : record.outcome == .timeout ? .orange : .secondary)
                    .help(record.detail)
            }.width(80)
            TableColumn("触发通知") { record in
                Text(record.notification.label).help(record.detail)
            }.width(138)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: RequestRecord.ID.self) { ids in
            if !ids.isEmpty {
                Button(ids.count == 1 ? "复制行" : "复制所选 \(ids.count) 行") {
                    let text = copyText(for: ids)
                    guard !text.isEmpty else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
        .onCopyCommand(perform: selectedRecordIDs.isEmpty ? nil : {
            [NSItemProvider(object: copyText(for: selectedRecordIDs) as NSString)]
        })
        .onChange(of: model.records.map(\.id)) { visibleIDs in
            selectedRecordIDs.formIntersection(visibleIDs)
        }
    }

    private func copyText(for ids: Set<RequestRecord.ID>) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        // 按表格顺序复制完整字段；制表符分列，换行分隔多条记录。
        return model.records.filter { ids.contains($0.id) }.map { record in
            [
                dateFormatter.string(from: record.startedAt),
                record.url,
                "\(record.elapsedMilliseconds.formatted(.number.precision(.fractionLength(0)))) ms",
                record.outcome.label,
                record.notification.label
            ].joined(separator: "\t")
        }.joined(separator: "\n")
    }

    private var footer: some View {
        HStack {
            Text("关闭窗口后继续监控 · 双击菜单栏圆点再次打开")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(action: model.previousPage) { Image(systemName: "chevron.left") }
                .disabled(model.pageIndex == 0).help("上一页")
            Text("\(model.pageIndex + 1) / \(model.pageCount)").font(.caption).monospacedDigit()
            Button(action: model.nextPage) { Image(systemName: "chevron.right") }
                .disabled(model.pageIndex + 1 >= model.pageCount).help("下一页")
        }.padding(.horizontal, 24).padding(.vertical, 12)
    }

    private func toggle() {
        if model.isRunning { model.stop(); return }
        do { _ = try MonitorSettings.validated(url: model.urlText, threshold: model.thresholdText, interval: model.intervalText) }
        catch { errorMessage = error.localizedDescription; return }
        isStarting = true
        Task { @MainActor in
            await notifications.requestPermission()
            do { try model.start() } catch { errorMessage = error.localizedDescription }
            isStarting = false
        }
    }
}
