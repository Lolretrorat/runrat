# AUR Files

This directory contains a `runrat-bin` PKGBUILD template for publishing RunRat to the Arch User Repository.

RunRat is currently a macOS AppKit application. The PKGBUILD expects future Linux release tarballs with this layout:

```text
runrat
runrat.desktop
runrat.png
LICENSE
```

To publish:

1. Build and upload `RunRat-linux-x86_64-<version>.tar.gz` and `RunRat-linux-aarch64-<version>.tar.gz` to the GitHub release.
2. Replace both `REPLACE_WITH_*_SHA256` values in [`PKGBUILD`](PKGBUILD).
3. Run `makepkg --printsrcinfo > .SRCINFO`.
4. Commit `PKGBUILD` and `.SRCINFO` to the AUR `runrat-bin` repository.

Install after publication:

```bash
yay -S runrat-bin
```
