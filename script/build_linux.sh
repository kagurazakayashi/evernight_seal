#!/bin/bash
set -e
# 建置 Linux 平台
# 先決條件：先執行 build_assets.sh
# 用法：於專案根目錄執行 script/build_linux.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Building Linux..."
cd "$PROJECT_DIR/flutter-build-all"
dart run flutter_build_all:build_all --config "$PROJECT_DIR/build.ini" --target "linux"

echo "Linux built."
