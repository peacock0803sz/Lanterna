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

## First launch and permissions

On first launch, grant exactly two permissions when asked:

- Accessibility
- Input Monitoring

Lanterna lists and switches windows through accessibility information. It does not need Screen Recording.

You can verify in System Settings → Privacy & Security that only these two entries exist for Lanterna.

## Usage

- `Cmd+Tab`: show the switcher. Keep holding `Cmd` and press `Tab` to move, release to switch.
- `Shift+Cmd+Tab`: move in the reverse direction.

## Troubleshooting

### Cmd+Tab shortcuts are not restored after a crash

Lanterna takes Cmd+Tab and Shift+Cmd+Tab away from the system while it runs and gives them back when it exits. After `kill -9` or a crash it cannot give them back, so both shortcuts stay off until something else puts them on.

Check that no Lanterna is running before doing anything else. Restoring writes the shortcuts back on without reading their current state, so running this while another Lanterna is up takes the hotkeys away from that process. Running more than one at a time is not supported.

```bash
pgrep -x Lanterna    # expect no output; run `pkill Lanterna` first if there is any
```

Then start Lanterna again and stop it cleanly, which lets its shutdown do the restoring.

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
