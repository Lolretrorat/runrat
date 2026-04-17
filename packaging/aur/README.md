# AUR Files

This directory contains the `runrat` PKGBUILD for publishing the Linux implementation of RunRat to the Arch User Repository.

The package builds the source tree in `linux/` and installs:

```text
/usr/bin/runrat
/usr/share/applications/runrat.desktop
/usr/share/runrat/icons/*.svg
/usr/share/pixmaps/runrat.svg
/usr/share/licenses/runrat/LICENSE
```

To publish:

1. Tag and publish a GitHub release such as `v1.0.2`.
2. Replace `REPLACE_WITH_SOURCE_TARBALL_SHA256` in [`PKGBUILD`](PKGBUILD) with the SHA-256 of `https://github.com/Lolretrorat/runrat/archive/refs/tags/v<version>.tar.gz`.
3. Run `makepkg --printsrcinfo > .SRCINFO`.
4. Build and lint on Arch with `makepkg -Csr` and `namcap`.
5. Commit `PKGBUILD` and `.SRCINFO` to the AUR `runrat` repository.

Install after publication:

```bash
yay -S runrat
```
