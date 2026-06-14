#!/usr/bin/env bash
# Replaces the Xcode host app bundle with the SPM-built Terminal Manager.app.
set -euo pipefail
cd "${SRCROOT}"
swift build -c debug
bash scripts/package-app.sh debug
DEST="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}"
mkdir -p "${BUILT_PRODUCTS_DIR}"
rm -rf "${DEST}"
ditto "${SRCROOT}/Terminal Manager.app/" "${DEST}/"
# Ad-hoc sign so XCUITest can launch the host on modern macOS.
codesign --force --deep --sign - --timestamp=none "${DEST}"
echo "Synced UI test host at $DEST"
