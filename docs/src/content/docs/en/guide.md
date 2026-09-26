---
title: Guide
description: Why Lanterna, requirements, and installation
---

## Why Lanterna

What sets Lanterna apart from the system switcher, AltTab, and Contexts:

- It takes no thumbnails and lists only app icons and window titles, Contexts-style. The switcher appears at once and uses almost no memory for captures.
- It switches windows in most-recently-used order, with type-to-filter search and shortcut hints.
- It needs only Accessibility and Input Monitoring. Window titles come from accessibility information, so Lanterna needs no Screen Recording.
- It runs on Apple Silicon only, supports Liquid Glass on Tahoe and later, and lives in the menu bar with no Dock icon.

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon (arm64) only

## Installation

### From the disk image

1. Download `Lanterna-X.Y.Z.dmg` from the GitHub Releases page
2. Open the disk image and drag `Lanterna.app` to `/Applications`

### With Homebrew

```bash
brew tap peacock0803sz/lanterna https://github.com/peacock0803sz/Lanterna
brew install --cask peacock0803sz/lanterna/lanterna
brew upgrade --cask peacock0803sz/lanterna/lanterna  # upgrade
```

## First launch and permissions

On first launch, Lanterna asks for these two permissions. Grant both.

- Accessibility
- Input Monitoring

:::note
Lanterna lists and switches windows through accessibility information. It does not need Screen Recording.
:::
