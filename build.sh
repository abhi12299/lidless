#!/bin/bash
# Build ClampshellToggler and assemble a runnable .app bundle (no Xcode GUI needed).
set -euo pipefail

APP_NAME="Lidless"
CONFIG="release"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

APP_DIR="$ROOT/dist/$APP_NAME.app"
echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "==> ad-hoc codesign"
# Apple Silicon requires at least an ad-hoc signature to execute; signing the whole
# bundle (the copied binary lost its linker signature) also lets Authorization
# Services trust the requester.
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --verbose=2 "$APP_DIR" || true

echo "==> done: $APP_DIR"
echo "    Run:     open \"$APP_DIR\""
echo "    Install: cp -R \"$APP_DIR\" /Applications/"
