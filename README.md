# 链接哨兵（LinkSentinel）

**简体中文** | [English](README.en.md)

<img src="Resources/AppIcon-preview.png" alt="链接哨兵应用图标" width="96">

一个原生 macOS 菜单栏链接监控小工具。使用 SwiftUI + AppKit，无第三方依赖，支持 macOS 13 及以上。

定时检测链接，在请求缓慢或失败时发送系统通知，完整记录每次请求的总耗时。关闭窗口后仍可在菜单栏继续监控。

## 下载与安装

1. 从 [Releases](https://github.com/sixlab/LinkSentinel/releases/latest) 下载 `LinkSentinel-v1.0.2-macOS-universal.zip`，支持 Apple Silicon 和 Intel Mac。
2. 解压后，将 `链接哨兵.app` 拖入“应用程序”目录；升级前先用 ⌘Q 退出旧版本。
3. 打开应用，点击“开启监控”，允许系统通知。

发布包使用本地临时签名（ad-hoc），尚未使用 Developer ID 签名或经 Apple 公证。首次打开可能被 Gatekeeper 拦截；确认来源可信后可参考 [Apple 的打开说明](https://support.apple.com/en-us/102445)，或按下文从源码构建。应用界面目前为简体中文。

每个 Release 提供 `SHA256SUMS.txt`，可将它和 ZIP 放在同一目录运行 `shasum -a 256 -c SHA256SUMS.txt` 核验下载。

## 从源码构建

需要完整 Xcode（含 macOS SDK）和 Swift 5.9 或更高版本。已在 Xcode 27.0 上验证；如果只安装了 Command Line Tools，请在 Xcode → Settings → Locations 中选择 Xcode 的命令行工具。

```bash
git clone https://github.com/sixlab/LinkSentinel.git
cd LinkSentinel
./scripts/build.sh --open
```

构建输出为 `build/链接哨兵.app`，可直接双击运行。

安装或更新到“应用程序”目录：先用 ⌘Q 退出旧实例，再执行 `./scripts/build.sh` 和 `./scripts/install.sh`，打开 `/Applications/链接哨兵.app`。安装脚本会核对应用身份并备份旧安装包，仅注册安装副本，避免开发目录副本抢占解析。

首次构建无需 Apple 开发者账号，脚本使用本机临时签名。版本变化见 [CHANGELOG.md](CHANGELOG.md)。

在 Xcode 中开发：打开 `LinkSentinel.xcodeproj`，选择 `LinkSentinel` scheme 和 `My Mac`，按 ⌘R。

## 使用

1. 启动后顶部菜单栏出现灰色圆点，同时打开设置窗口并显示 Dock 图标；链接框自动聚焦并全选。
2. 默认链接为 `https://www.google.com`，告警阈值为 **1000 毫秒**，时间间隔为 **5 秒**。
3. 点击“开启监控”，允许系统通知，即刻开始第一次请求。
4. **灰色：未开启；绿色：监控中；黄色：超时；红色：失败。** 网络、DNS/TLS 和 HTTP 错误显示红色；下次请求正常后恢复绿色。
5. 关闭窗口会隐藏 Dock 图标，保留菜单栏并继续监控。双击菜单栏圆点再次打开窗口时，Dock 图标恢复；右键菜单可打开窗口、停止监控或退出。最小化窗口保留 Dock 图标。
6. 点击“停止监控”取消进行中的请求。停止后可修改配置，重新开启。

快捷键：⌘Return 开启/停止，⌘W 关闭窗口，⌘Q 退出。监控时链接仍可选中复制，其余配置需停止后修改。

## 请求与通知规则

- 使用 HTTP GET，跟随系统支持的重定向，禁用响应缓存；耗时覆盖从发起请求到接收完整响应（包括 DNS、连接和 TLS）。收到的数据直接丢弃，不在内存中积攒响应正文。
- 告警阈值不会中断请求。接收完整响应后记录总耗时，超过阈值时显示黄色“超时”并通知。网络失败、DNS/TLS 错误、HTTP 4xx/5xx 显示红色“失败”并通知，即使耗时已经超过阈值。底层连接仍遵循 URLSession 默认网络超时规则，发生传输超时也会记录实际耗时和失败原因。
- 阈值支持 1～3600000 的整数毫秒；间隔支持 0.1～86400 秒。
- 相邻请求开始时间至少相隔设定的间隔；请求串行执行。如果单次耗时超过间隔，则在本次结束后发起下一次，不并发补发积压请求。
- 每次异常触发一条通知。历史表中显示开始时间、链接、耗时、结果、通知发送状态，鼠标悬停结果可看具体原因。
- “是 · 已发送”表示系统已接受通知；右上角是否显示横幅仍受系统通知样式、专注模式控制。请在 **系统设置 → 通知 → 链接哨兵** 中允许通知并开启横幅。
- 未授权通知时仍可监控，但会显示权限提示，历史中明确标记“未发送 · 未授权”。前台窗口打开时也支持横幅。
- 停止时进行中的请求记为“已取消”，不触发异常通知。退出后重开默认不启动监控。
- 系统睡眠时不会持续请求，唤醒后继续。工具不阻止系统睡眠，也不安装后台守护服务。

## 历史与设置

- 所有请求历史保存在 `~/Library/Application Support/LinkSentinel/history.sqlite`，每页显示 100 条，使用底部箭头翻页；不会自动删除旧记录。
- 配置通过系统 UserDefaults 保存，域为 `com.local.linksentinel.desktop`；首次从旧域 `com.local.LinkSentinel` 迁移，不删除旧数据。历史留在本机，不上传其他服务；监控本身仅请求你设置的链接。
- 数据库写入失败会停止监控并显示错误；不会自动覆盖损坏的历史文件。

## 测试

```bash
./scripts/test.sh
```

自动测试使用可控的 URLProtocol 替代外部 HTTP 传输，覆盖慢响应完整结束、完整响应体总耗时、阈值后的失败判定与手动取消逻辑；SQLite 使用临时数据库验证持久化和分页。

## 目录

```text
Sources/MonitorCore/       输入校验、请求探测、监控调度、SQLite 历史
Sources/LinkSentinel/      菜单栏、原生窗口、SwiftUI 表格、系统通知
Tests/MonitorCoreTests/    自动化行为测试
Resources/Info.plist       macOS 应用配置
Resources/Assets.xcassets/ 应用图标资源目录
LinkSentinel.xcodeproj/    可直接打开的 Xcode 工程
scripts/                  构建与测试命令
docs/                     设计与版本发布说明
```

实现使用 Apple 的 [NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar) 和 [UserNotifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications) 原生 API。

应用图标为原创蓝色监控心跳图案。`Resources/Assets.xcassets/AppIcon.appiconset` 包含全部 macOS 尺寸，由 Xcode 编译为 `Assets.car` 和兼容 ICNS，并通过 `CFBundleIconName` / `CFBundleIconFile` 声明。采用 Apple 的[标准图标资源目录配置](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)，供系统识别应用。通知左侧的应用图标由 macOS 根据应用身份和资源决定，设置 Dock 的运行时图标不会直接设置通知图标。

修改矢量绘制后可执行 `swift scripts/generate-icon.swift`，同时更新资源目录、独立的 `Resources/AppIcon.icns` 和预览图；独立 ICNS 不再重复加入 Copy Bundle Resources。菜单栏圆点继续用于显示实时状态。

构建脚本直接生成 `build/链接哨兵.app` 并刷新该路径的系统注册，避免构建目录副本抢占 Bundle ID 的解析。更新后应先退出正在运行的旧进程，再打开新版应用；直接再次打开 `.app` 可能只是唤起旧进程。可执行 `swift scripts/verify-app-icon.swift` 检查注册路径以及资源和系统图标服务的实际渲染，验证过程不读取屏幕。

## 贡献与许可证

欢迎通过 [Issues](https://github.com/sixlab/LinkSentinel/issues) 报告问题或提交改进，开发约定见 [CONTRIBUTING.md](CONTRIBUTING.md)。提交问题时请隐藏链接中可能包含的账号、令牌或内部地址。

采用 [MIT License](LICENSE)，Copyright © 2026 sixlab contributors。
