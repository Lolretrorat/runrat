# RunRat

RunRat is a native macOS menu bar utility that shows a small running rat whose animation speed reflects current system load.

The app is inspired by the playful menu bar activity concept popularised by RunCat, reworked here as an original rat-based macOS utility.

The app is built with Swift, SwiftUI and AppKit only. It runs as a menu bar app, keeps the Dock clear, and uses a fixed-frame rat animation rendered at menu bar size with aspect ratio preserved.

## Features

- Native macOS menu bar app
- Fixed 6-frame rat animation loop
- RunCat365-style playback speed logic
- CPU, GPU and memory speed sources
- One-second metric sampling
- Compact dashboard with live system stats
- No external dependencies

## Project Structure

- [`RunRatApp.swift`](RunRat/RunRatApp.swift): SwiftUI app entry point
- [`AppDelegate.swift`](RunRat/AppDelegate.swift): app lifecycle and startup wiring
- [`StatusBarController.swift`](RunRat/StatusBarController.swift): menu bar item, popover and animation loop
- [`SystemMetricsMonitor.swift`](RunRat/SystemMetricsMonitor.swift): CPU, GPU, memory, storage, battery and network sampling
- [`RatIconRenderer.swift`](RunRat/RatIconRenderer.swift): rat frame asset loading
- [`DashboardView.swift`](RunRat/DashboardView.swift): popover UI
- [`generate-rat-assets.swift`](scripts/generate-rat-assets.swift): rat animation and app icon generator

## Running

1. Open [`RunRat.xcodeproj`](RunRat.xcodeproj) in Xcode.
2. Select the `RunRat` scheme.
3. Run on `My Mac`.

The app launches as a menu bar utility with no Dock icon.

## Animation

The rat uses the `runRat0` to `runRat5` asset sequence in [`Assets.xcassets`](RunRat/Assets.xcassets). Frame order is fixed. Only playback interval changes.

To regenerate the rat frame PNGs and app icons:

```bash
mkdir -p /tmp/clang-cache
CLANG_MODULE_CACHE_PATH=/tmp/clang-cache swift scripts/generate-rat-assets.swift
```

## Release

Create a signed macOS release zip:

```bash
./scripts/package-release.sh
```

If notarising, run the package step first and then:

```bash
NOTARY_PROFILE=<profile-name> ./scripts/notarize-release.sh
```

## Homebrew

The cask template lives at [`packaging/homebrew/Casks/runrat.rb`](packaging/homebrew/Casks/runrat.rb). After publishing a GitHub release, update the cask `version` and `sha256`, then copy it into a Homebrew tap.

## Arch Linux

The AUR packaging template lives at [`packaging/aur/PKGBUILD`](packaging/aur/PKGBUILD).

RunRat is currently implemented with AppKit and SwiftUI, so the functional app is macOS-only. The AUR template is ready for a future Linux release tarball, but a Linux implementation is required before `yay -S runrat-bin` can install a working Arch package.

## Notes

- The menu bar icon is scaled by height only.
- Aspect ratio is preserved.
- GPU load falls back to CPU when GPU data is unavailable.

## Licence

This repository is licensed under the MIT License. See [LICENSE](LICENSE).
