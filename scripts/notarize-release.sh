#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/RunRat.xcodeproj"
BUILD_DIR="$ROOT_DIR/build"
EXPORT_DIR="$BUILD_DIR/export"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$EXPORT_DIR/RunRat.app"

MARKETING_VERSION="$(ruby -e 'print File.read(ARGV[0])[/MARKETING_VERSION = ([^;]+);/, 1].to_s.strip' "$PROJECT_PATH/project.pbxproj")"
VERSION="${MARKETING_VERSION:-1.0}"
ZIP_NAME="RunRat-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
SHA_PATH="$DIST_DIR/$ZIP_NAME.sha256"

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "NOTARY_PROFILE is required."
  echo "Create one with:"
  echo "  xcrun notarytool store-credentials <profile-name> --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>"
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Signed app not found at $APP_PATH"
  echo "Run ./scripts/package-release.sh first."
  exit 1
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Distribution zip not found at $ZIP_PATH"
  echo "Run ./scripts/package-release.sh first."
  exit 1
fi

echo "Submitting $ZIP_NAME for notarisation"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling notarisation ticket to RunRat.app"
xcrun stapler staple "$APP_PATH"

echo "Repacking notarised app"
rm -f "$ZIP_PATH" "$SHA_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"

echo
echo "Notarised artefacts:"
echo "  $APP_PATH"
echo "  $ZIP_PATH"
echo "  $SHA_PATH"
