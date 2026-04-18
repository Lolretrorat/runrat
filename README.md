# RunRat

RunRat is a small system activity monitor that shows a running rat whose animation speed reflects current system load.

The app is inspired by the playful menu bar activity concept popularised by RunCat, reworked here as an original rat-based utility.

The repository now contains separate platform implementations:

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

1. Open [`macos/RunRat.xcodeproj`](macos/RunRat.xcodeproj) in Xcode.
2. Select the `RunRat` scheme.
3. Run on `My Mac`.

The app launches as a menu bar utility with no Dock icon.

The rat uses the `runRat0` to `runRat5` asset sequence in [`Assets.xcassets`](macos/RunRat/Assets.xcassets). Frame order is fixed. Only playback interval changes.

To regenerate the rat frame PNGs and app icons:

```bash
cd macos
mkdir -p /tmp/clang-cache
CLANG_MODULE_CACHE_PATH=/tmp/clang-cache swift scripts/generate-rat-assets.swift
```

Create a signed macOS release zip:

```bash
cd macos
./scripts/package-release.sh
```

If notarising, run the package step first and then:

```bash
cd macos
NOTARY_PROFILE=<profile-name> ./scripts/notarize-release.sh
```

## Linux

Install from the Arch User Repository:

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

The cask template lives at [`packaging/homebrew/Casks/runrat.rb`](packaging/homebrew/Casks/runrat.rb). After publishing a signed and notarised macOS release zip, update the cask `version` and `sha256`, then copy it into a Homebrew tap.

## Arch Linux

RunRat is packaged for Arch Linux as [`runrat`](https://aur.archlinux.org/packages/runrat) in the AUR. Install it with an AUR helper:

```bash
yay -S runrat
```

The packaging source lives in [`packaging/aur`](packaging/aur). It builds the Linux implementation from the tagged GitHub source archive and installs the tray app, desktop entry, icons and MIT license file.

To publish an update, bump [`PKGBUILD`](packaging/aur/PKGBUILD), refresh `.SRCINFO`, validate with `makepkg` on Arch, then push those two files to the AUR Git repository.

## Notes

- The macOS menu bar icon is scaled by height only and preserves aspect ratio.
- GPU load falls back to CPU when GPU data is unavailable.
- Linux tray support depends on the desktop environment exposing AppIndicator/status notifier items.

## Licence

This repository is licensed under the MIT License. See [LICENSE](LICENSE).
