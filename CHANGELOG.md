# 更新记录 / Changelog

## 1.0.3 · 2026-09-23

构建号 9。

- 改用 HEAD 请求，收到响应头后结束计时，不下载正文、不跟随重定向。
- 将默认链接改为 `https://www.gstatic.com/generate_204`，一次性迁移旧默认地址，保留自定义配置。
- 将黄色状态及历史结果“超时”重命名为“延迟高”，同步更新通知。
- 在监控按钮旁添加“重置”，停止时可恢复三个输入框的默认值，保留历史记录。
- 历史列表支持单选、多选、右键复制行和 ⌘C，按列表顺序复制完整的五列内容。

Build 9.

- Use HEAD requests and measure time to response headers, without downloading bodies or following redirects.
- Default to `https://www.gstatic.com/generate_204`, upgrading the old default once while preserving custom settings.
- Rename the yellow status and history outcome to `延迟高` (high latency), including notification wording.
- Add a Reset button beside the monitoring button to restore the three default inputs while stopped, preserving history.
- Select one or multiple history rows and copy all five columns in display order using the context menu or ⌘C.

## 1.0.2 · 2026-09-23

首次公开发布，构建号为 6。

- 将应用中文名称统一为“链接哨兵”。
- 请求超过告警阈值时继续完成请求，记录包含完整响应体的总耗时。
- 保留菜单栏监控、系统通知、四种状态、SQLite 历史和偏好迁移。
- 提供 macOS 13+ 的 Apple Silicon / Intel 通用应用包。
- 补充中英文使用文档、贡献说明和 MIT 许可证。

First public release, build 6.

- Introduce the Chinese app name “链接哨兵”.
- Let slow requests finish and record the total duration of the complete response.
- Include menu bar monitoring, notifications, four status colors, SQLite history, and settings migration.
- Provide a universal macOS 13+ app for Apple Silicon and Intel.
- Add Chinese and English documentation, contribution guidelines, and the MIT license.
