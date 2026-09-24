## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon (arm64) only

## Permissions

Lanterna needs exactly two system permissions:

- Accessibility
- Input Monitoring

It does not need Screen Recording.

## A note on Gatekeeper

Lanterna is distributed as a self-built disk image with an ad-hoc signature. It is not notarized and not distributed through the App Store.

On first launch, macOS Gatekeeper may refuse to open the app. If that happens, right-click (or Control-click) `Lanterna.app` and choose Open, then confirm. Alternatively, remove the quarantine attribute:

```bash
xattr -d com.apple.quarantine /Applications/Lanterna.app
```
