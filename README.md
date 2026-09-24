# Lanterna

![artwork](https://img.p3ac0ck.net/figs/Lanterna.png)

A list-style window switcher for macOS.

## Why Lanterna

Compared with the system switcher and other switchers such as AltTab and Contexts:

- It shows a Contexts-style list of app icon and window title with no thumbnails, so the switcher appears at once and uses almost no memory for captures.
- It asks for Accessibility and Input Monitoring only. Window titles come from accessibility information, so Lanterna needs no Screen Recording and avoids the weekly re-confirmation dialog.
- It switches at window level in most-recently-used order, with type-to-filter search and shortcut hints.
- It runs Apple Silicon only with Liquid Glass on Tahoe, lives in the menu bar with no Dock icon, and keeps its floating panel in memory with a sub-30 ms show target.

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

Under Privacy & Security in System Settings, confirm that only these two entries belong to Lanterna.

## Usage

- `Cmd+Tab` shows the switcher. Keep holding `Cmd` and press `Tab` to move, then release `Cmd` to switch.
- `Shift+Cmd+Tab` moves in the reverse direction.

## Troubleshooting

### Cmd+Tab shortcuts are not restored after a crash

Lanterna takes Cmd+Tab and Shift+Cmd+Tab away from the system while it runs and gives them back when it exits. After `kill -9` or a crash it cannot give them back, so both shortcuts stay off until something else restores them.

Check that no Lanterna is running before doing anything else. Restoring turns the shortcuts back on without reading their current state, so running this while another Lanterna is up takes the shortcuts away from that process. Running more than one at a time is not supported.

```bash
pgrep -x Lanterna    # expect no output; run `pkill Lanterna` first if there is any
```

Then start Lanterna again and stop it cleanly, so its shutdown restores the shortcuts.

```bash
/Applications/Lanterna.app/Contents/MacOS/Lanterna &
sleep 1
pkill Lanterna
```

If the shortcuts are still off after that, log out and back in. The system's assignment is per login session.

### Windows do not appear

Check that the two permissions above are granted, then relaunch Lanterna.

## For developers

See [CONTRIBUTING](CONTRIBUTING.md) for the development setup, build, and test instructions.

## License

See [LICENSE](LICENSE).
