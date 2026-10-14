#!/bin/zsh
set -eu
ROOT="${0:A:h}"
DEST="${1:-$ROOT/build/KeyRow.app}"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources" "$ROOT/.build"
cp "$ROOT/Info.plist" "$DEST/Contents/Info.plist"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 -module-cache-path "$ROOT/.build/module-cache" "$ROOT/Sources/Model.swift" "$ROOT/Sources/Hyper.swift" "$ROOT/Sources/Overlay.swift" "$ROOT/Sources/Engine.swift" "$ROOT/Sources/Settings.swift" "$ROOT/Sources/main.swift" -o "$DEST/Contents/MacOS/KeyRow" -framework AppKit -framework SwiftUI -framework ApplicationServices -framework ServiceManagement
codesign --force --sign - --identifier local.keyrow.app --requirements '=designated => identifier "local.keyrow.app"' "$DEST"
"$DEST/Contents/MacOS/KeyRow" --self-test
echo "Built $DEST"
