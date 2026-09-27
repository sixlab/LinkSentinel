# 更新记录 / Changelog

## 1.0.5 · 2026-09-27

构建号 11。

- 按固定发起间隔调度请求，允许慢请求重叠，通知发送不阻塞后续请求。
- 请求达到告警阈值仍未完成时立即记录延迟高，失败立即记录；每个请求仅判定一次连续异常。
- 请求继续完成并更新同一条历史的实际耗时；进行中的慢请求显示耗时下限。
- 并发时按判定事件顺序累计，迟到的完成回调不重复计数、不覆盖较新的状态。
- 在网络队列上协调阈值与响应完成，避免界面卡顿把正常请求误报为延迟高。
- 停止取消全部请求与阈值计时，退出等待落盘，兼容原有历史并恢复中断记录。

Build 11.

- Launch requests on a fixed cadence, allowing overlap without waiting for slow responses or notification delivery.
- Judge unfinished requests at the alert threshold and record failures immediately, counting each request only once.
- Keep requests running and update the same history row with the final duration; show a lower bound while waiting.
- Count verdicts in detection order and prevent late completions from recounting or replacing newer status.
- Coordinate threshold and completion events on the network queue so UI stalls cannot misclassify normal responses as high latency.
- Cancel all requests and deadlines on stop, await persistence on quit, and recover interrupted rows while preserving existing history.

## 1.0.4 · 2026-09-23

构建号 10。

- 新增“连续异常次数”输入框，默认 3，支持保存、正整数校验和重置。
- 延迟高和失败混合累计，每连续达到设定次数通知一次；默认第 3、6、9 次通知，正常、取消或停止后清零。
- 状态颜色仍实时反映每次请求结果，历史详情记录本轮异常计数。
- 读取旧配置时为新增次数补默认值，保留已有链接、阈值和间隔。
- 在中英文 README 中说明项目由 AI 开发，以及人提供需求和反馈的协作方式。

Build 10.

- Add a persisted positive-integer consecutive-anomaly input, defaulting to 3 and included in Reset.
- Count high latency and failures together, notifying after each group (by default, the 3rd, 6th, 9th, and so on). Normal responses, cancellation, or stopping clear the count.
- Keep status colors immediate and include the current group count in history details.
- Preserve existing settings when adding the new default limit during decoding.
- Document the project's AI development process and human requirements/feedback in both READMEs.

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
