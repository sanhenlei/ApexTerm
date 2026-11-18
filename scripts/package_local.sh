#!/usr/bin/env bash
# 本地快速打包（仅供本机安装使用，不用于正式发布）：
#   ad-hoc 签名免公证；跳过 Tart VM / UI 验收 / 测试门禁（正式发布仍走 scripts/build_app.sh）。
#
# 用法:
#   scripts/package_local.sh [VERSION]          增量 Release 构建 + 安全扫描 + ad-hoc 签名 + DMG + SHA256
#   scripts/package_local.sh --install [VERSION] 同上，但直接安装到 /Applications（保留一次回滚备份），不产出 DMG
#   scripts/package_local.sh --test  [VERSION]  打包前先跑 swift test 全量门禁
#
# 版本默认对齐上游最新 Release（1.23.6）：带 -local 后缀会被 SemVer 判为预发布版，
# 应用内更新器会误提示"可更新到上游同名版本"。DMG 产出到 ~/Downloads。
# 依赖 SPM 缓存: 代码未改动时构建约 0.5s；单模块改动约 20-30s（WMO 整模块重编）。
set -euo pipefail

RUN_TESTS=0
INSTALL_MODE=0
VERSION=""
for arg in "$@"; do
    case "$arg" in
        --test) RUN_TESTS=1 ;;
        --install) INSTALL_MODE=1 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) if [ -n "$VERSION" ]; then echo "❌ 多余的参数: $arg" >&2; exit 1; fi
           VERSION="$arg" ;;
    esac
done
VERSION="${VERSION:-1.23.6}"
BUILD_NUMBER="$(date +%Y%m%d)01"

# 工具链探测（按顺序兜底）：
# 1) 环境变量 DEVELOPER_DIR（完整 Xcode，最干净）
# 2) /Applications/Xcode.app 或 ~/Downloads/Xcode.app
# 3) 仅装 CLT 的机器：27.x SDK 把 SwiftUI @State 宏化（SwiftUIMacros 插件只随
#    完整 Xcode 分发），回退到 MacOSX26.5.sdk（仍是经典属性包装器）即可编译。
if [ -z "${DEVELOPER_DIR:-}" ]; then
    if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    elif [ -d "$HOME/Downloads/Xcode.app/Contents/Developer" ]; then
        export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
    fi
fi
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]; then
    echo "ℹ️  未检测到完整 Xcode，使用 CLT + MacOSX26.5.sdk 编译（绕过 27.x SDK 的 SwiftUIMacros 依赖）"
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
fi

APP_NAME="AetherTerm.app"
BUILD_DIR=".build"
APP_DIR="${BUILD_DIR}/${APP_NAME}"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
DIST_DMG="${HOME}/Downloads/AetherTerm-v${VERSION}-macos-arm64.dmg"
SHA_FILE="${HOME}/Downloads/AetherTerm-v${VERSION}-macos-arm64.sha256"
mkdir -p "${HOME}/Downloads"

if [ ! -d Resources ] || [ ! -f scripts/verify_bundle_security.py ]; then
    echo "❌ 请在项目根目录运行: scripts/package_local.sh" >&2
    exit 1
fi

if [ "$RUN_TESTS" = "1" ]; then
    echo "🧪 [Local Gate] swift test ..."
    swift test > "${BUILD_DIR}/test-local.log" 2>&1 || { tail -20 "${BUILD_DIR}/test-local.log"; exit 1; }
    echo "✅ 测试门禁通过（日志: ${BUILD_DIR}/test-local.log）"
fi

echo "⚡ Release 构建 v${VERSION} (${BUILD_NUMBER}) ..."
swift build -c release --product ApexTerm

echo "📦 组装 ${APP_NAME} ..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "Resources/ApexTerm.icns" "${RESOURCES_DIR}/ApexTerm.icns"

RELEASE_BIN=".build/out/Products/Release/ApexTerm"
[ -f "${RELEASE_BIN}" ] || RELEASE_BIN="$(find .build -type f -perm -111 -name ApexTerm | grep -i release | head -1)"
echo "📋 主程序: ${RELEASE_BIN}"
cp "${RELEASE_BIN}" "${MACOS_DIR}/ApexTerm"
/usr/bin/strip -S "${MACOS_DIR}/ApexTerm"
chmod +x "${MACOS_DIR}/ApexTerm"

SSHPASS="$(command -v sshpass || true)"
if [ -n "${SSHPASS}" ]; then
    echo "📦 捆绑 sshpass: ${SSHPASS}"
    cp "${SSHPASS}" "${MACOS_DIR}/sshpass"
    chmod +x "${MACOS_DIR}/sshpass"
else
    echo "ℹ️  未安装 sshpass，密码认证回退 PTY 提示自动填充"
fi

cat << EOF > "${APP_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ApexTerm</string>
    <key>CFBundleIdentifier</key>
    <string>com.apexterm.app</string>
    <key>CFBundleName</key>
    <string>AetherTerm</string>
    <key>CFBundleDisplayName</key>
    <string>AetherTerm</string>
    <key>CFBundleIconFile</key>
    <string>ApexTerm</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>连接你选择的局域网 SSH 服务器，并进行 SFTP 文件传输和系统监控。</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
</dict>
</plist>
EOF
plutil -lint "${APP_DIR}/Contents/Info.plist" > /dev/null

# Xcode 不在 /Applications 时（如 ~/Downloads），链接器会把工具链绝对路径写进
# LC_RPATH，触发零捆绑红线的开发者家目录扫描；本地包一律清除含 $HOME 的 rpath。
RPATHS="$(otool -l "${MACOS_DIR}/ApexTerm" \
    | awk '/LC_RPATH/{f=1;next} f && $1=="path"{print $2; f=0}' \
    | grep "^${HOME}/" || true)"
for rp in ${RPATHS}; do
    echo "🧹 移除开发者目录 rpath: ${rp}"
    install_name_tool -delete_rpath "${rp}" "${MACOS_DIR}/ApexTerm"
done

# rpath 清理在扫描前完成，确保零捆绑红线校验的是最终产物。
python3 scripts/verify_bundle_security.py "${APP_DIR}"

codesign --force --deep --sign - "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

if [ "$INSTALL_MODE" = "1" ]; then
    echo "📲 安装到 /Applications/${APP_NAME} ..."
    if pgrep -x ApexTerm > /dev/null 2>&1; then
        echo "ℹ️  应用正在运行；本次替换将在下次启动 AetherTerm 时生效"
    fi
    if [ -d "/Applications/${APP_NAME}" ]; then
        BACKUP_DIR="${BUILD_DIR}/installed-backup-$(date +%Y%m%d%H%M%S)"
        mkdir -p "${BACKUP_DIR}"
        mv "/Applications/${APP_NAME}" "${BACKUP_DIR}/ApexTerm.app"
        python3 scripts/prune_build_artifacts.py --installed-backups-only
        echo "💾 旧版已备份: ${BACKUP_DIR}"
    fi
    cp -R "${APP_DIR}" "/Applications/${APP_NAME}"
else
    echo "💿 制作 DMG ..."
    TMP_DMG_DIR=$(mktemp -d /tmp/apexterm_dmg.XXXXXX)
    cp -R "${APP_DIR}" "${TMP_DMG_DIR}/"
    ln -s /Applications "${TMP_DMG_DIR}/Applications"
    hdiutil create -volname "AetherTerm" -fs HFS+ -srcfolder "${TMP_DMG_DIR}" \
        -ov -format UDZO "${DIST_DMG}" -quiet
    rm -rf "${TMP_DMG_DIR}"
    (cd "$(dirname "${DIST_DMG}")" && shasum -a 256 "$(basename "${DIST_DMG}")") > "${SHA_FILE}"
    cat "${SHA_FILE}"
fi

echo ""
echo "✅ 本地打包完成（ad-hoc 签名，仅供本机安装，严禁对外分发）"
if [ "$INSTALL_MODE" = "1" ]; then
    echo "📍 已安装: /Applications/${APP_NAME}"
else
    echo "📍 DMG: ${DIST_DMG}"
fi
