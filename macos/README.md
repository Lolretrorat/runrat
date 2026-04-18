# RunRat for macOS

This is the native macOS implementation of RunRat. It is built with Swift, SwiftUI and AppKit, runs as an accessory menu bar app, and keeps the Dock clear.

## Requirements

- macOS 13 Ventura or newer
- Xcode for building from source
- Apple Developer ID certificate for signing public release builds

## Run

1. Open `RunRat.xcodeproj` in Xcode.
2. Select the `RunRat` scheme.
3. Run on `My Mac`.

## Assets

The rat animation uses the `runRat0` to `runRat5` image sequence in `RunRat/Assets.xcassets`.

To regenerate the rat frame PNGs and app icons:

```bash
mkdir -p /tmp/clang-cache
CLANG_MODULE_CACHE_PATH=/tmp/clang-cache swift scripts/generate-rat-assets.swift
```

## Release

Maintainers can create a release zip with:

```bash
./scripts/package-release.sh
```

Notarise and staple public release builds before publishing:

```bash
NOTARY_PROFILE=<profile-name> ./scripts/notarize-release.sh
```

Before updating the Homebrew cask, verify the exported app:

```bash
codesign --verify --deep --strict --verbose=2 build/export/RunRat.app
spctl --assess --type execute --verbose build/export/RunRat.app
shasum -a 256 dist/RunRat-<version>.zip
```
