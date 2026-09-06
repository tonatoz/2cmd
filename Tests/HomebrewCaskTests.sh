#!/usr/bin/env bash
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
Tools/make-homebrew-cask.sh 1.2.3 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef > "$tmp/2cmd.rb"

HOMEBREW_NO_AUTO_UPDATE=1 brew ruby - "$tmp/2cmd.rb" "$tmp" <<'RUBY'
require "cask/cask_loader"
require "cask/config"
require "fileutils"

cask = Cask::CaskLoader::FromContentLoader.new(File.read(ARGV.fetch(0))).load(config: nil)
raise "incorrect version" unless cask.version.to_s == "1.2.3"
raise "incorrect checksum" unless cask.sha256.to_s == "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
raise "incorrect download URL" unless cask.url.to_s == "https://github.com/tonatoz/2cmd/releases/download/v1.2.3/2cmd.dmg"

appdir = File.join(ARGV.fetch(1), "Applications with spaces")
cask.config = Cask::Config.new(explicit: { appdir: appdir })
app = File.join(appdir, "2cmd.app")
FileUtils.mkdir_p(app)
file = File.join(app, "executable")
File.write(file, "fixture")
system("/usr/bin/xattr", "-w", "com.apple.quarantine", "0081;00000000;Homebrew;", file, exception: true)

hook = cask.artifacts.find { |artifact| artifact.is_a?(Cask::Artifact::PostflightSteps) }
raise "missing postflight_steps" unless hook
Homebrew::InstallSteps::Runner.new(context: cask).run(hook.steps)
attributes = IO.popen(["/usr/bin/xattr", file], &:read)
raise "quarantine was not removed" if attributes.lines.map(&:strip).include?("com.apple.quarantine")
raise "app contents changed" unless File.read(file) == "fixture"
puts "Homebrew cask generation: metadata and recursive quarantine removal passed"
RUBY
