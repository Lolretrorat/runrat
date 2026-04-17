# Homebrew Tap Files

This directory contains the Homebrew cask definition for the macOS implementation of RunRat.

To publish via a tap:

1. Build, sign and notarise the macOS app from `macos/`.
2. Publish a GitHub release containing `RunRat-<version>.zip`.
3. Replace `REPLACE_WITH_RUNRAT_ZIP_SHA256` in [`Casks/runrat.rb`](Casks/runrat.rb) with the release zip SHA-256.
4. Copy [`Casks/runrat.rb`](Casks/runrat.rb) into `Casks/runrat.rb` in your tap repository.
5. Push the tap repository to GitHub.

Install:

```bash
brew tap Lolretrorat/tap
brew install --cask runrat
```
