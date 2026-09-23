#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE_APP="$PWD/build/链接哨兵.app"
INSTALLED_APP="/Applications/链接哨兵.app"
LEGACY_APP="/Applications/LinkSentinel.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "请先执行 ./scripts/build.sh。" >&2
  exit 1
fi
SOURCE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")
if [[ "$SOURCE_ID" != "com.local.linksentinel.desktop" ]]; then
  echo "构建产物不是当前正式版，请先重新构建。" >&2
  exit 1
fi
if /usr/bin/pgrep -x LinkSentinel >/dev/null; then
  echo "请先通过 ⌘Q 退出链接哨兵（LinkSentinel），再执行安装。" >&2
  exit 1
else
  PROCESS_STATUS=$?
  if [[ "$PROCESS_STATUS" != 1 ]]; then
    echo "无法确认旧应用是否已退出，安装已停止。" >&2
    exit 1
  fi
fi
codesign --verify --deep --strict "$SOURCE_APP"
for EXISTING_APP in "$INSTALLED_APP" "$LEGACY_APP"; do
  [[ -e "$EXISTING_APP" ]] || continue
  EXISTING_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$EXISTING_APP/Contents/Info.plist")
  case "$EXISTING_ID" in
    com.local.LinkSentinel|com.local.linksentinel.desktop) ;;
    *) echo "安装位置存在其他应用，已停止。" >&2; exit 1 ;;
  esac
done
mkdir -p .build/previous-installation
BACKUP_DIR=$(mktemp -d "$PWD/.build/previous-installation/upgrade.XXXXXX")
if [[ -e "$INSTALLED_APP" ]]; then
  ditto "$INSTALLED_APP" "$BACKUP_DIR/链接哨兵.app"
fi
ditto "$SOURCE_APP" "$INSTALLED_APP"
codesign --verify --deep --strict "$INSTALLED_APP"
touch "$INSTALLED_APP"
if [[ -e "$LEGACY_APP" ]]; then
  "$LSREGISTER" -u "$LEGACY_APP"
  mv "$LEGACY_APP" "$BACKUP_DIR/LinkSentinel.app"
fi
"$LSREGISTER" -u "$SOURCE_APP"
"$LSREGISTER" -f "$INSTALLED_APP"
echo "已安装：$INSTALLED_APP"
