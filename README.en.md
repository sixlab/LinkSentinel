# LinkSentinel · 链接哨兵

[简体中文](README.md) | **English**

<img src="Resources/AppIcon-preview.png" alt="LinkSentinel app icon" width="96">

A native macOS menu bar utility that checks a URL periodically, sends system notifications for slow or failed requests, and records the total duration of every request. Built with SwiftUI and AppKit, with no third-party dependencies. Requires macOS 13 or later. The app's interface is currently in Simplified Chinese.

## Download and install

1. Download `LinkSentinel-v1.0.2-macOS-universal.zip` from [Releases](https://github.com/sixlab/LinkSentinel/releases/latest). It supports both Apple Silicon and Intel Macs.
2. Extract the archive and drag `链接哨兵.app` into Applications. Quit an older version with ⌘Q before upgrading.
3. Open the app, click `开启监控` (Start monitoring), and allow notifications.

Release builds are ad-hoc signed; they are not Developer ID signed or notarized by Apple. Gatekeeper may block the first launch. If you trust the download, follow [Apple's instructions](https://support.apple.com/en-us/102445), or build the app from source below.

Each release includes `SHA256SUMS.txt`. Place it beside the downloaded ZIP and run `shasum -a 256 -c SHA256SUMS.txt` to verify the download.

## Build from source

Install full Xcode with the macOS SDK and Swift 5.9 or later. The project has been verified with Xcode 27.0. If you only have Command Line Tools selected, choose Xcode under Xcode → Settings → Locations → Command Line Tools.

```bash
git clone https://github.com/sixlab/LinkSentinel.git
cd LinkSentinel
./scripts/build.sh --open
```

The resulting app is `build/链接哨兵.app`. No Apple Developer account is needed for the local ad-hoc signing used by the build script.

To install or update, quit the running app with ⌘Q, then run:

```bash
./scripts/build.sh
./scripts/install.sh
open /Applications/链接哨兵.app
```

The installer validates app identities, backs up the previous installation, and registers the installed copy. It moves an older English-named `LinkSentinel.app` into the project's `.build/previous-installation/` backup directory. Settings and history are preserved.

For development in Xcode, open `LinkSentinel.xcodeproj`, select the `LinkSentinel` scheme and `My Mac`, then press ⌘R. See [CHANGELOG.md](CHANGELOG.md) for version history.

## Usage

- Default URL: `https://www.google.com`. Alert threshold: **1,000 ms**. Interval: **5 seconds**.
- The URL field is focused and its contents selected whenever the main window opens.
- Click `开启监控` to start immediately, or `停止监控` to stop. Settings can be changed while stopped; the URL remains selectable for copying while monitoring.
- Closing the window hides the Dock icon and keeps monitoring in the menu bar. Double-click the menu bar dot to reopen the window. Right-click it to open the window, stop monitoring, or quit. Minimizing keeps the Dock icon visible.
- Keyboard shortcuts: ⌘Return to start/stop, ⌘W to close the window, and ⌘Q to quit.

| Color | Status | Meaning |
| --- | --- | --- |
| Gray | 未开启 | Stopped |
| Green | 监控中 | Monitoring; latest completed request was normal |
| Yellow | 超时 | Completed request exceeded the alert threshold |
| Red | 失败 | Network, DNS, TLS, or HTTP failure |

## Requests and notifications

- Uses HTTP GET, follows system-supported redirects, and disables response caching. Timing covers the complete response, including DNS, connection setup, TLS, and the response body. Incoming body bytes are discarded instead of accumulating in memory.
- **The alert threshold never cancels a request.** After the complete response arrives, its total duration is recorded. A successful HTTP 2xx/3xx response over the threshold is marked slow and triggers a notification.
- Network errors, DNS/TLS errors, and HTTP 4xx/5xx responses are failures even if they also exceed the threshold. URLSession's default transport timeouts still apply; transport failures record the actual elapsed time and error.
- Thresholds accept integer values from 1 to 3,600,000 milliseconds; intervals accept 0.1 to 86,400 seconds.
- Requests run serially. Start times are separated by at least the configured interval. If a request takes longer, the next starts after it finishes; missed intervals do not create a backlog of parallel requests.
- Each failed or slow request triggers one notification after it finishes. History shows start time, URL, total duration, outcome, and notification delivery status. Hover over an outcome for details.
- “Sent” means macOS accepted the notification. Banner visibility also depends on notification settings and Focus. Enable notifications for `链接哨兵` in System Settings → Notifications. Monitoring and history still work if permission is denied.
- Stopping cancels the current request and records it as cancelled without an alert. Relaunching leaves monitoring stopped.
- Requests pause during system sleep and continue after waking. The app does not prevent sleep or install a background daemon.

## Local data

- History is stored in `~/Library/Application Support/LinkSentinel/history.sqlite`, with 100 records per page and no automatic deletion.
- Settings are stored in the `com.local.linksentinel.desktop` UserDefaults domain. Settings from the older `com.local.LinkSentinel` domain are migrated once, without overwriting existing current settings.
- History stays on your Mac. Monitoring sends requests only to the configured URL and any redirects it follows; there is no analytics service.
- A database write failure stops monitoring and displays an error instead of silently replacing the history database.

## Tests

```bash
./scripts/test.sh
```

The tests replace external HTTP transport with controlled URLProtocol responses while exercising real timing, classification, cancellation, scheduling, and SQLite persistence. They cover complete slow responses, streaming response duration, failures after the threshold, manual cancellation, settings migration, history persistence, and pagination.

## Project layout

```text
Sources/MonitorCore/       Validation, network probes, scheduling, SQLite history
Sources/LinkSentinel/      Menu bar, native window, SwiftUI table, notifications
Tests/MonitorCoreTests/    Automated behavioral tests
Resources/Info.plist       App metadata
Resources/Assets.xcassets/ App icon asset catalog
LinkSentinel.xcodeproj/    Xcode project
scripts/                  Build, install, test, and icon utilities
docs/                     Design and release notes
```

The app uses Apple's public NSStatusBar and UserNotifications APIs. The original blue heartbeat icon is compiled from `Resources/Assets.xcassets/AppIcon.appiconset`. Run `swift scripts/generate-icon.swift` to regenerate the icon catalog and preview after editing its vector drawing. Run `swift scripts/verify-app-icon.swift` to check the built app's registration and icon rendering without capturing the screen.

## Contributing and license

Bug reports and improvements are welcome through [Issues](https://github.com/sixlab/LinkSentinel/issues) and pull requests. See [CONTRIBUTING.md](CONTRIBUTING.md). Remove credentials, tokens, and private URLs before sharing logs or screenshots.

Released under the [MIT License](LICENSE). Copyright © 2026 sixlab contributors.
