#!/usr/bin/env bash
# Build Terminal Manager.app and run XCUITest suite.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Running XCUITest (builds app via Xcode host target)..."
rm -rf "$ROOT/.build/UITestResults.xcresult"
xcodebuild test \
  -project TerminalManager.xcodeproj \
  -scheme TerminalManagerUITests \
  -destination 'platform=macOS' \
  -resultBundlePath "$ROOT/.build/UITestResults.xcresult" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- \
  AD_HOC_CODE_SIGNING_ALLOWED=YES

echo "UI tests passed."
