# Homebrew Tap Files

This directory contains the Homebrew cask template for the macOS implementation of RunRat.

Once published in a tap, install with:

```bash
brew tap Lolretrorat/tap
brew install --cask runrat
```

## Maintainer Publishing

1. Build, sign and notarise the macOS app from `macos/`.
2. Publish a GitHub release containing `RunRat-<version>.zip`.
3. Replace `REPLACE_WITH_RUNRAT_ZIP_SHA256` in [`Casks/runrat.rb`](Casks/runrat.rb) with the release zip SHA-256.
4. Copy [`Casks/runrat.rb`](Casks/runrat.rb) into `Casks/runrat.rb` in the tap repository.
5. Push the tap repository to GitHub.
