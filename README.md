# Lanterna

A list-style window switcher for macOS.

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon (arm64) only

## Distribution

Lanterna is distributed as a self-built disk image with an ad-hoc signature. It is not notarized and not distributed through the App Store.

On first launch, macOS Gatekeeper may refuse to open the app. If that happens, right-click (or Control-click) `Lanterna.app` and choose Open, then confirm. Alternatively, remove the quarantine attribute:

```bash
xattr -d com.apple.quarantine /Applications/Lanterna.app
```

## Installation

### From the disk image

1. Download `Lanterna-X.Y.Z.dmg` from the GitHub Releases page (alpha versions are marked as prereleases).
2. Open the disk image and drag `Lanterna.app` to `/Applications`.

### With Homebrew

```bash
brew tap peacock0803sz/lanterna https://github.com/peacock0803sz/Lanterna
brew install --cask peacock0803sz/lanterna/lanterna
```

To upgrade:

```bash
brew upgrade --cask peacock0803sz/lanterna/lanterna
```
