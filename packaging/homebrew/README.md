# Homebrew Tap Files

This directory contains the Homebrew cask definition for RunRat.

To publish via a tap:

1. Publish a GitHub release containing `RunRat-<version>.zip`.
2. Replace `REPLACE_WITH_RUNRAT_ZIP_SHA256` in [`Casks/runrat.rb`](Casks/runrat.rb) with the release zip SHA-256.
3. Copy [`Casks/runrat.rb`](Casks/runrat.rb) into `Casks/runrat.rb` in your tap repository.
4. Push the tap repository to GitHub.

Install:

```bash
brew tap Lolretrorat/tap
brew install --cask runrat
```
