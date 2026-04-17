# Repository Guidelines

## Project Structure & Module Organization

RunRat has separate native implementations by platform. `macos/` holds the Swift, SwiftUI, and AppKit menu bar app, with source in `macos/RunRat/`, assets in `macos/RunRat/Assets.xcassets/`, release scripts in `macos/scripts/`, and the Xcode project at `macos/RunRat.xcodeproj`. `linux/` contains the GTK 3 and Ayatana AppIndicator app, with C source in `linux/src/main.c`, icons in `linux/assets/`, install metadata in `linux/packaging/`, and rules in `linux/CMakeLists.txt`. Distribution recipes live in `packaging/homebrew/` and `packaging/aur/`.

## Build, Test, and Development Commands

- `cmake -S linux -B build/linux -DCMAKE_BUILD_TYPE=Release`: configure the Linux build.
- `cmake --build build/linux`: compile the Linux tray app.
- `./build/linux/runrat`: run the Linux app from the build tree.
- `cmake --install build/linux --prefix /usr/local`: install the Linux app and desktop assets.
- `open macos/RunRat.xcodeproj`: open the macOS project in Xcode, then run the `RunRat` scheme on `My Mac`.
- `cd macos && CLANG_MODULE_CACHE_PATH=/tmp/clang-cache swift scripts/generate-rat-assets.swift`: regenerate macOS rat frames and app icons.
- `cd macos && ./scripts/package-release.sh`: create a signed macOS release zip.

## Coding Style & Naming Conventions

Swift code uses four-space indentation, `final class` where appropriate, `PascalCase` for types, and `camelCase` for methods and properties. Keep AppKit/SwiftUI responsibilities separated across the existing controller, monitor, renderer, and view files. C code uses two-space indentation, C11, GLib/GTK types, `snake_case` for functions, and `PascalCase` for structs. Linux builds use `-Wall -Wextra -Wpedantic`; keep new code warning-free.

## Testing Guidelines

There is no dedicated automated test suite yet. Verify changes by building the affected platform and launching the app. For Linux, run the CMake commands above and smoke-test tray animation, CPU/memory/network menu values, and icon loading. For macOS, run from Xcode and check menu bar animation, popover metrics, quit behavior, and asset rendering. For releases, also run the verification commands in `macos/README.md`.

## Commit & Pull Request Guidelines

History currently uses short, imperative commit messages such as `initial commit`. Continue with concise summaries like `Fix Linux icon path fallback` or `Update macOS release script`. Pull requests should describe the platform affected, summarize user-visible behavior, list manual verification steps, and include screenshots or short screen recordings for UI changes. Link related issues when available and call out packaging or signing implications.

## Security & Configuration Tips

Do not commit Developer ID certificates, notarization credentials, generated archives, or local build output. Keep `NOTARY_PROFILE` and signing configuration in the local keychain or environment. Validate package checksums before updating Homebrew or AUR metadata.
