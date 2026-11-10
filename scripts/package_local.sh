#!/usr/bin/env bash
# Local ad-hoc packaging: builds a launchable AetherTerm.app without Developer ID
# signing or notarization (marked "-local"). Official release gates remain the
# domain of scripts/build_app.sh on a maintainer machine.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.23.3-local"
BUILD_NUMBER="$(date +%Y%m%d)01"
APP_DIR=".build/AetherTerm.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

echo "🧪 Local test gate..."
swift test --skip testTerminalFontManagerFastEnumerationUnder150ms --skip testBenchmark2_VTParserColorParsingThroughput --quiet

echo "⚡ Release build (arm64)..."
swift build -c release

echo "📦 Assembling bundle (v${VERSION} Build ${BUILD_NUMBER})..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "Resources/ApexTerm.icns" "${RESOURCES_DIR}/ApexTerm.icns"

RELEASE_BIN=".build/arm64-apple-macosx/release/ApexTerm"
[ -f "${RELEASE_BIN}" ] || RELEASE_BIN=$(find .build -type f -perm -111 -name ApexTerm | grep -i release | head -1)
echo "Using release binary: ${RELEASE_BIN}"
cp "${RELEASE_BIN}" "${MACOS_DIR}/ApexTerm"
/usr/bin/strip -S "${MACOS_DIR}/ApexTerm"
chmod +x "${MACOS_DIR}/ApexTerm"

SSHPASS="$(command -v sshpass || true)"
if [ -n "${SSHPASS}" ]; then
    echo "🔑 Bundling sshpass helper from ${SSHPASS}"
    cp "${SSHPASS}" "${MACOS_DIR}/sshpass"
    chmod +x "${MACOS_DIR}/sshpass"
else
    echo "⚠️ sshpass not found locally; password auth falls back to PTY prompt autofill."
fi

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ApexTerm</string>
    <key>CFBundleIdentifier</key><string>com.apexterm.app</string>
    <key>CFBundleName</key><string>AetherTerm</string>
    <key>CFBundleDisplayName</key><string>AetherTerm</string>
    <key>CFBundleIconFile</key><string>ApexTerm</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>连接你选择的局域网 SSH 服务器，并进行 SFTP 文件传输和系统监控。</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSRequiresAquaSystemAppearance</key><false/>
</dict>
</plist>
EOF

echo "🛡️ Zero-bundle security scan..."
python3 scripts/verify_bundle_security.py "${APP_DIR}"

echo "✍️ Ad-hoc codesign..."
codesign --force --deep --sign - "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

cd .build
rm -f AetherTerm-local-macos-arm64.zip AetherTerm-${VERSION}-macos-arm64.dmg
zip -qry AetherTerm-local-macos-arm64.zip AetherTerm.app
STAGING=$(mktemp -d /tmp/aetherterm_dmg.XXXXXX)
cp -R AetherTerm.app "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"
hdiutil create -volname "AetherTerm" -fs HFS+ -srcfolder "${STAGING}" -ov -format UDZO "AetherTerm-${VERSION}-macos-arm64.dmg" -quiet
rm -rf "${STAGING}"
cd ..

echo "✅ Local packaging complete:"
echo "   📲 App:  ${APP_DIR}"
echo "   🗜️ Zip:  .build/AetherTerm-local-macos-arm64.zip"
echo "   💿 DMG:  .build/AetherTerm-${VERSION}-macos-arm64.dmg"
