# AUR Files

This directory contains the `runrat` Arch User Repository package for the Linux implementation of RunRat.

The package builds the tagged GitHub source archive and installs:

```text
/usr/bin/runrat
/usr/share/applications/runrat.desktop
/usr/share/runrat/icons/*.svg
/usr/share/pixmaps/runrat.svg
/usr/share/licenses/runrat/LICENSE
```

Install after publication:

```bash
yay -S runrat
```

## Publishing

1. Update `pkgver` in [`PKGBUILD`](PKGBUILD) and keep it in sync with `linux/CMakeLists.txt`.
2. Commit the release changes in the main repository.
3. Tag and push the matching GitHub release tag, such as `v1.0.3`.
4. Download `https://github.com/Lolretrorat/runrat/archive/refs/tags/v<version>.tar.gz` and update `sha256sums` in the AUR copy of `PKGBUILD`.
5. Run `makepkg --printsrcinfo > .SRCINFO`.
6. Build and lint on Arch with `makepkg -Csr` and `namcap` when available.
7. Commit `PKGBUILD` and `.SRCINFO` to the AUR `runrat` repository.

Keep the repository copy of [`PKGBUILD`](PKGBUILD) as a template with `REPLACE_WITH_SOURCE_TARBALL_SHA256`. The source archive includes this directory, so committing the live checksum here would change the archive and invalidate the checksum used by AUR.

For a new AUR package:

```bash
git clone ssh://aur@aur.archlinux.org/runrat.git
cp PKGBUILD .SRCINFO runrat/
cd runrat
git add PKGBUILD .SRCINFO
git commit -m "Add runrat package"
git push
```
