# Contrubition Guidelines

- (MUST) Write in English for all documents, including comments in source
- (MUST) Use .gitmessage for commit template

## Prerequisites

- macOS 15 (Sequoia) or later
- [Nix](https://nixos.org/) with flakes enabled
- Xcode with Command Line Tools (for Swift compiler and macOS SDK)

### Nix Setup

Ensure your `~/.config/nix/nix.conf` includes:

```
experimental-features = nix-command flakes
```

### Xcode Setup

If Xcode CLI tools are not installed:

```bash
xcode-select --install
```

## Development

Enter the development shell:

```bash
nix develop
```

This provides `swiftformat`, `swiftlint`, and installs pre-commit hooks automatically.

### Build and Test

The target architecture is pinned rather than left to the host, so the triple is given on every build: the architecture is a property of the product, not of whichever machine happens to build it. `scripts/test.sh` passes it for you, along with the search paths Swift Testing needs when only the Command Line Tools are installed.

```bash
swift build --triple arm64-apple-macosx15.0
lipo -archs .build/debug/Lanterna   # must print arm64 and nothing else
bash scripts/test.sh
```

### CI-to-Local Command Mapping

| CI Step | Local Command |
|---------|---------------|
| nix-validate | `nix flake check` |
| swift-build (build) | `nix develop --command swift build --triple arm64-apple-macosx15.0` |
| swift-build (verify architecture) | `lipo -archs .build/debug/Lanterna \| grep -qx arm64` |
| swift-build (test) | `nix develop --command swift test --triple arm64-apple-macosx15.0` |

## Troubleshooting

### `swift` not found

Ensure Xcode is installed and `xcode-select -p` points to your Xcode installation:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### Nix not found

Install Nix: https://nixos.org/download/

### Slow first `nix develop`

The first invocation downloads and builds dependencies. Subsequent runs use the cached Nix store. Expected cold-start: under 5 minutes.
