#!/usr/bin/env bash
set -euo pipefail

version="1.2.3"
sha256="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

expected=$(cat <<'EOF'
cask "2cmd" do
  version "1.2.3"
  sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  url "https://github.com/tonatoz/2cmd/releases/download/v#{version}/2cmd.dmg"
  name "2cmd"
  desc "Switch keyboard layouts with the left and right Command keys"
  homepage "https://github.com/tonatoz/2cmd"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "2cmd.app"

  # Homebrew quarantines every download, unconditionally: the --no-quarantine flag
  # and its HOMEBREW_CASK_OPTS equivalent were removed in July 2026. A quarantined
  # build signed with an unknown certificate chain is spawned and then held by
  # Gatekeeper before main() runs, so the app appears in Activity Monitor with no
  # menu bar icon and no window. Dropping the flag here is what makes the app
  # launchable at all until the release is notarized.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/2cmd.app"]
  end

  uninstall quit: "dev.anton.2cmd"

  zap trash: "~/Library/Preferences/dev.anton.2cmd.plist"

  caveats <<~EOS
    2cmd is signed with a project certificate and is not notarized, so this cask
    clears the quarantine flag Homebrew attaches to the download — otherwise
    Gatekeeper holds the app before it starts and it never reaches the menu bar.

    Then enable 2cmd in System Settings → Privacy & Security → Accessibility.
  EOS
end
EOF
)

actual=$(Tools/make-homebrew-cask.sh "$version" "$sha256")

if [[ "$actual" != "$expected" ]]; then
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual")
  exit 1
fi

printf 'Homebrew cask generation\n  ok   — deterministic version, checksum, install, and cleanup metadata\n'
