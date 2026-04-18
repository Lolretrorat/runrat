# RunRat for Linux

This is the Linux implementation of RunRat. It is a GTK 3 and Ayatana AppIndicator tray utility that animates a small rat icon based on current CPU load and exposes live CPU, memory and network readings from the tray menu.

## Dependencies

- C compiler
- CMake 3.16 or newer
- pkgconf
- GTK 3 development headers
- Ayatana AppIndicator development headers

## Install

Once the AUR package is available, install RunRat on Arch Linux with:

```bash
yay -S runrat
```

The package installs the tray app, desktop entry, SVG animation frames and license file under standard system paths.

On Arch Linux:

```bash
sudo pacman -S --needed base-devel cmake pkgconf gtk3 libayatana-appindicator
```

## Build

```bash
cmake -S linux -B build/linux -DCMAKE_BUILD_TYPE=Release
cmake --build build/linux
```

Run from the build tree:

```bash
./build/linux/runrat
```

Install:

```bash
cmake --install build/linux --prefix /usr/local
```

## Packaging

The AUR packaging template in [`../packaging/aur`](../packaging/aur) builds this implementation from the tagged GitHub source archive and installs:

- `/usr/bin/runrat`
- `/usr/share/applications/runrat.desktop`
- `/usr/share/runrat/icons/*.svg`
- `/usr/share/pixmaps/runrat.svg`
- `/usr/share/licenses/runrat/LICENSE`

Maintainers publish updates by bumping the package version, updating the source checksum in the AUR copy, regenerating `.SRCINFO`, validating with `makepkg`, and pushing `PKGBUILD` plus `.SRCINFO` to the AUR `runrat` repository.
