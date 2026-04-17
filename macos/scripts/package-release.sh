#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/RunRat.xcodeproj"
SCHEME="RunRat"
CONFIGURATION="Release"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_DIR="$BUILD_DIR/RunRat.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$EXPORT_DIR/RunRat.app"

MARKETING_VERSION="$(ruby -e 'print File.read(ARGV[0])[/MARKETING_VERSION = ([^;]+);/, 1].to_s.strip' "$ROOT_DIR/RunRat.xcodeproj/project.pbxproj")"
VERSION="${MARKETING_VERSION:-1.0}"
ZIP_NAME="RunRat-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
SHA_PATH="$DIST_DIR/$ZIP_NAME.sha256"

XCODEBUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "platform=macOS"
  -archivePath "$ARCHIVE_DIR"
  archive
)

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  XCODEBUILD_ARGS+=(
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
  )
fi

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  XCODEBUILD_ARGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
  )
fi

rm -rf "$ARCHIVE_DIR" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR" "$DIST_DIR"

echo "Building $SCHEME $VERSION"

xcodebuild "${XCODEBUILD_ARGS[@]}"

cp -R "$ARCHIVE_DIR/Products/Applications/RunRat.app" "$APP_PATH"

rm -f "$ZIP_PATH" "$SHA_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"

echo
echo "Created:"
echo "  $ZIP_PATH"
echo "  $SHA_PATH"
