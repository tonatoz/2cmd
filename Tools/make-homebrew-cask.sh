#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 VERSION SHA256" >&2
  exit 2
fi

version=$1
sha256=$2

cat <<EOF
cask "2cmd" do
  version "$version"
  sha256 "$sha256"

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

  uninstall quit: "dev.anton.2cmd"

  zap trash: "~/Library/Preferences/dev.anton.2cmd.plist"

  caveats <<~EOS
    2cmd is signed with a project certificate and is not notarized, and
    Homebrew quarantines everything it downloads. Gatekeeper spawns a quarantined
    build and then holds it before it runs: the process is listed in Activity
    Monitor, but no menu bar icon ever appears. Clear the flag once:

      xattr -dr com.apple.quarantine "#{appdir}/2cmd.app"
      open "#{appdir}/2cmd.app"

    Installing with "brew install --cask --no-quarantine tonatoz/tap/2cmd" skips
    the flag. Then enable 2cmd in System Settings → Privacy & Security → Accessibility.
  EOS
end
EOF
