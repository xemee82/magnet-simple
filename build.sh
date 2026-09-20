#!/bin/bash
set -euo pipefail

APP_NAME="MagnetSimple"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "🔨 清理旧构建文件..."
rm -rf "${APP_BUNDLE}" "${BUILD_DIR}"/*.dmg "${BUILD_DIR}"/*.zip "${BUILD_DIR}/dmg_root"
mkdir -p "${BUILD_DIR}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

echo "📦 编译 Swift 源码为 Universal Binary (arm64 + x86_64)..."
TMP_ARM64="/tmp/${APP_NAME}_arm64"
TMP_X86="/tmp/${APP_NAME}_x86_64"
rm -f "${TMP_ARM64}" "${TMP_X86}"

swiftc \
    -target arm64-apple-macos13.0 \
    -O \
    -o "${TMP_ARM64}" \
    Sources/MagnetSimple/main.swift \
    Sources/MagnetSimple/AppDelegate.swift \
    Sources/MagnetSimple/HotKeyManager.swift \
    Sources/MagnetSimple/WindowManager.swift \
    -framework AppKit \
    -framework Carbon \
    -framework ApplicationServices \
    -framework ServiceManagement

swiftc \
    -target x86_64-apple-macos13.0 \
    -O \
    -o "${TMP_X86}" \
    Sources/MagnetSimple/main.swift \
    Sources/MagnetSimple/AppDelegate.swift \
    Sources/MagnetSimple/HotKeyManager.swift \
    Sources/MagnetSimple/WindowManager.swift \
    -framework AppKit \
    -framework Carbon \
    -framework ApplicationServices \
    -framework ServiceManagement

echo "🔗 合并为 Universal 通用二进制..."
lipo -create "${TMP_ARM64}" "${TMP_X86}" -output "${MACOS}/${APP_NAME}"
chmod 755 "${MACOS}/${APP_NAME}"
rm -f "${TMP_ARM64}" "${TMP_X86}"

echo "📋 复制 Info.plist 与资源..."
cp Resources/Info.plist "${CONTENTS}/Info.plist"
cp Resources/AppIcon.icns "${RESOURCES}/AppIcon.icns"
cp Resources/MenuBarIcon.png "${RESOURCES}/MenuBarIcon.png"
cp Resources/MenuBarIcon@2x.png "${RESOURCES}/MenuBarIcon@2x.png"
cp Resources/使用说明.md "${BUILD_DIR}/使用说明.md"
cp Resources/shortcuts_demo.png "${BUILD_DIR}/shortcuts_demo.png"

echo "🧹 清除扩展属性与隔离标记..."
xattr -cr "${APP_BUNDLE}" || true

echo "🔏 执行指定 Designated Requirement 的 Ad-hoc 代码签名..."
codesign --force --deep -s - -r='designated => identifier "com.tylerh.magnetsimple"' "${APP_BUNDLE}"

echo "🔍 校验代码签名..."
codesign -vvv --deep --strict "${APP_BUNDLE}"

echo "🔄 刷新系统 LaunchServices 图标缓存..."
touch "${APP_BUNDLE}"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "${APP_BUNDLE}" 2>/dev/null || true

echo "📦 生成保持完整 Unix 权限的绿色 ZIP 包..."
ditto -c -k --keepParent "${APP_BUNDLE}" "${BUILD_DIR}/MagnetSimple.zip"

echo ""
echo "✅ 构建成功:"
echo "   - 原生应用: ${APP_BUNDLE}"
echo "   - 绿色压缩包 (发送给同事): ${BUILD_DIR}/MagnetSimple.zip"
echo "   - 使用说明: ${BUILD_DIR}/使用说明.md"
echo "   首次使用请在「系统设置 → 隐私与安全性 → 辅助功能」中授权。"
