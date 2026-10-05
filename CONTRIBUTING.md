# Contributing

2cmd switches keyboard input sources through configurable physical-key bindings.
Left and right Command are the defaults. Bug reports and focused fixes are welcome.
For a larger feature, open an issue first so we can agree on its scope.

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

The checks are standalone executables, not XCTest. The project supports Command Line
Tools without requiring a test framework or external dependencies. `make test` runs
gesture recognition, isolated settings persistence, and Homebrew cask checks.

Test observable input-source choices and event propagation in
`Tests/KeyBindingDetectorTests.swift`. Test persistence and configuration validation through
`Settings` in `Tests/SettingsTests.swift`, using an isolated `UserDefaults` domain.
Verify AppKit interactions and actual input-source switching in the running app.

## Publishing releases

Pushing a `v*` tag starts the Release workflow. It builds that tag and publishes
`2cmd.zip` and `2cmd.dmg`. If the release already exists, the workflow uploads
the packages without replacing existing files.
The workflow writes the tag version without its leading `v` into
`CFBundleShortVersionString` and `CFBundleVersion` before building and signing.
It verifies both fields before uploading the packages.

If publication fails, run the current workflow against the original tag:

```sh
gh workflow run release.yml --ref main -f tag=v2.0.0
```

Replace `v2.0.0` with the target tag. Do not move the tag or delete the release.
Wait for both packages to appear before synchronizing the Homebrew tap.
The tap schedules synchronization hourly. To start it immediately:

```sh
gh workflow run sync-2cmd.yml --repo tonatoz/homebrew-tap
```

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
