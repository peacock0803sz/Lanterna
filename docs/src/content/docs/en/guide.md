---
title: Guide
description: Why Lanterna, requirements, and installation
---

## Why Lanterna

Compared with the system switcher and other switchers such as AltTab and Contexts:

- It shows a Contexts-style list of app icon and window title with no thumbnails, so the switcher appears at once and uses almost no memory for captures.
- It switches at window level in most-recently-used order, with type-to-filter search and shortcut hints.
- It asks for Accessibility and Input Monitoring only. Window titles come from accessibility information, so Lanterna needs no Screen Recording.
- It runs Apple Silicon only with Liquid Glass on Tahoe, lives in the menu bar with no Dock icon.

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon (arm64) only

## Installation

### From the disk image

1. Download `Lanterna-X.Y.Z.dmg` from the GitHub Releases page. Alpha versions are marked as prereleases.
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

## First launch and permissions

On first launch, grant exactly two permissions when asked:

- Accessibility
- Input Monitoring

Lanterna lists and switches windows through accessibility information. It does not need Screen Recording.
