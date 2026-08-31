# Contributing

2cmd is a small, deliberately narrow utility: it watches solo ⌘ taps and switches the
keyboard layout. Bug reports and small fixes are very welcome. If you have a larger
feature in mind, please open an issue first so we can agree on whether it belongs here
before you spend time on the code.

## Prerequisites

- macOS 15 or newer
- Swift toolchain — the Command Line Tools are enough, full Xcode is not required
- No external dependencies; SwiftPM builds the whole thing from this repository

## Getting started

```sh
git clone https://github.com/tonatoz/2cmd.git
cd 2cmd
make test           # run the state machine checks
make app            # build dist/2cmd.app
make signing-cert   # once, before the first install
make install        # build, sign, copy to /Applications
```

`make signing-cert` creates a local `2cmd Local Signing` certificate so every rebuild
keeps the same code signing identity and the Accessibility permission is not
invalidated each time you rebuild.

## Before opening a pull request

- `make test` and `make lint` must pass.
- Keep the change focused — one topic per pull request.
- Write commit messages and code comments in English.

## Testing

The checks are a plain executable, not XCTest: neither XCTest nor swift-testing ships
with the Command Line Tools, and the project deliberately depends on nothing else.
`make test` builds and runs it. New behaviour in the detector should come with a case in
`Tests/SoloTapDetectorTests.swift`.

## Reporting bugs

Please include:

- your macOS version;
- your Mac model, and whether it is Apple silicon or Intel;
- the input sources enabled in System Settings → Keyboard → Input Sources;
- whether the menu bar icon is dimmed (that means interception is off or the
  Accessibility permission is missing).

Diagnostics can be read with:

```sh
log show --last 5m --predicate 'subsystem == "dev.anton.2cmd"' --info
```
