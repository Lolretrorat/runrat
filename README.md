# RunRat

RunRat is a small system activity monitor that shows a running rat whose animation speed reflects current system load.

The app is inspired by the playful menu bar activity concept popularised by RunCat, reworked here as an original rat-based utility.

The repository contains separate platform implementations:

- `macos/`: native macOS menu bar app built with Swift, SwiftUI and AppKit.
- `linux/`: GTK 3 and Ayatana AppIndicator tray app for Linux desktops.
- `packaging/`: Homebrew cask and Arch AUR packaging files.

## Features

- Native macOS menu bar app
- GTK 3 and AppIndicator Linux tray app
- Fixed 6-frame rat animation loop
- RunCat365-style playback speed logic
- macOS CPU, GPU and memory speed sources
- Linux CPU-driven tray animation with CPU, memory and network menu stats
- One-second metric sampling
- Compact macOS dashboard with live system stats

## Project Structure

- [`macos/RunRatApp.swift`](macos/RunRat/RunRatApp.swift): SwiftUI app entry point
- [`macos/AppDelegate.swift`](macos/RunRat/AppDelegate.swift): app lifecycle and startup wiring
- [`macos/StatusBarController.swift`](macos/RunRat/StatusBarController.swift): menu bar item, popover and animation loop
- [`macos/SystemMetricsMonitor.swift`](macos/RunRat/SystemMetricsMonitor.swift): CPU, GPU, memory, storage, battery and network sampling
- [`macos/RatIconRenderer.swift`](macos/RunRat/RatIconRenderer.swift): rat frame asset loading
- [`macos/DashboardView.swift`](macos/RunRat/DashboardView.swift): popover UI
- [`macos/generate-rat-assets.swift`](macos/scripts/generate-rat-assets.swift): macOS rat animation and app icon generator
- [`linux/src/main.c`](linux/src/main.c): Linux GTK tray implementation
- [`linux/CMakeLists.txt`](linux/CMakeLists.txt): Linux build and install rules

## macOS

RunRat for macOS is built from [`macos/`](macos). It runs as a menu bar utility with no Dock icon.

1. Open [`macos/RunRat.xcodeproj`](macos/RunRat.xcodeproj) in Xcode.
2. Select the `RunRat` scheme.
3. Run on `My Mac`.

The rat uses the `runRat0` to `runRat5` asset sequence in [`Assets.xcassets`](macos/RunRat/Assets.xcassets). Frame order is fixed. Only playback interval changes.

To regenerate the rat frame PNGs and app icons:

```bash
cd macos
mkdir -p /tmp/clang-cache
CLANG_MODULE_CACHE_PATH=/tmp/clang-cache swift scripts/generate-rat-assets.swift
```

Maintainers can create a signed macOS release zip with:

```bash
cd macos
./scripts/package-release.sh
```

If notarising a public release, run the package step first and then:

```bash
cd macos
NOTARY_PROFILE=<profile-name> ./scripts/notarize-release.sh
```

## Linux

RunRat for Linux is built from [`linux/`](linux). It uses GTK 3 and Ayatana AppIndicator for desktop tray integration.

On Arch Linux, install from the AUR once the package is available:

```bash
yay -S runrat
```

Install build dependencies on Arch Linux:

```bash
sudo pacman -S --needed base-devel cmake pkgconf gtk3 libayatana-appindicator
```

Build and run:

```bash
cmake -S linux -B build/linux -DCMAKE_BUILD_TYPE=Release
cmake --build build/linux
./build/linux/runrat
```

Install locally:

```bash
cmake --install build/linux --prefix /usr/local
```

## Homebrew

The Homebrew cask template lives at [`packaging/homebrew/Casks/runrat.rb`](packaging/homebrew/Casks/runrat.rb). It is intended for a public tap after a signed and notarised macOS release zip is available.

## Arch Linux

The Arch Linux package is named [`runrat`](https://aur.archlinux.org/packages/runrat) in the AUR. Once it is published, install it with an AUR helper:

```bash
yay -S runrat
```

The packaging template lives in [`packaging/aur`](packaging/aur). The AUR copy builds the Linux implementation from the tagged GitHub source archive and installs the tray app, desktop entry, icons and MIT license file.

Maintainers publishing an update should bump [`PKGBUILD`](packaging/aur/PKGBUILD), refresh `.SRCINFO`, validate with `makepkg` on Arch, then push those two files to the AUR Git repository.

## Contributing

Issues and pull requests are welcome. Please include the affected platform, the user-visible behavior changed, and the build or smoke-test steps you ran. Screenshots or short recordings are especially helpful for menu bar, tray, icon and popover changes.

## Notes

- The macOS menu bar icon is scaled by height only and preserves aspect ratio.
- GPU load falls back to CPU when GPU data is unavailable.
- Linux tray support depends on the desktop environment exposing AppIndicator/status notifier items.

## Licence

This repository is licensed under the MIT License. See [LICENSE](LICENSE).
