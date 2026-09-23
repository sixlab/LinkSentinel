#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodebuild -project LinkSentinel.xcodeproj -scheme LinkSentinel -configuration Release \
  -derivedDataPath "$PWD/build/DerivedData" \
  CONFIGURATION_BUILD_DIR="$PWD/build" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build
codesign --verify --deep --strict "$PWD/build/链接哨兵.app"
touch "$PWD/build/链接哨兵.app"
# 最终应用直接由 Xcode 生成，避免复制后目录时间戳及 Launch Services 仍指向旧副本。
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
LEGACY_BUILD_APP="$PWD/build/DerivedData/Build/Products/Release/LinkSentinel.app"
if [[ -d "$LEGACY_BUILD_APP" ]]; then
  "$LSREGISTER" -u "$LEGACY_BUILD_APP"
fi
if [[ -d "$PWD/build/LinkSentinel.app" ]]; then
  "$LSREGISTER" -u "$PWD/build/LinkSentinel.app"
  mkdir -p .build/previous-build
  mv "$PWD/build/LinkSentinel.app" "$PWD/.build/previous-build/LinkSentinel-$(date +%Y%m%d%H%M%S).app"
fi
"$LSREGISTER" -f "$PWD/build/链接哨兵.app"
echo "已构建：$PWD/build/链接哨兵.app"
if [[ "${1:-}" == "--open" ]]; then
  open "$PWD/build/链接哨兵.app"
fi
