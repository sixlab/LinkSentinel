# 贡献指南 / Contributing

欢迎提交问题或 Pull Request。

1. 使用完整 Xcode 打开 `LinkSentinel.xcodeproj`，或运行 `./scripts/build.sh`。
2. 修改请求、状态或持久化行为时，添加能够复现该行为的测试。
3. 提交前运行 `./scripts/test.sh` 和 `./scripts/build.sh`。
4. 用户可见行为变更请同步维护 `README.md` 与 `README.en.md`。
5. 提交信息使用简体中文的 Conventional Commits，例如 `fix(probe): 修复慢响应耗时记录`。

Issue 请注明 macOS 版本、应用版本、预期行为和复现步骤。不要上传令牌、私有链接或包含敏感信息的历史数据库。构建产物、个人 Xcode 配置和本地运行数据不提交到源码仓库。

## English

Issues and pull requests are welcome.

1. Open `LinkSentinel.xcodeproj` with full Xcode, or run `./scripts/build.sh`.
2. Add a regression test when changing request, state, or persistence behavior.
3. Run `./scripts/test.sh` and `./scripts/build.sh` before submitting.
4. Keep both README translations in sync when changing user-facing behavior.
5. Use Conventional Commits with Simplified Chinese subjects, for example `fix(probe): 修复慢响应耗时记录`.

Include macOS and app versions, expected behavior, and reproduction steps in bug reports. Omit credentials, private URLs, and sensitive history databases. Keep build artifacts, personal Xcode settings, and local runtime data out of commits.
