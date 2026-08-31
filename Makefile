APP_NAME := 2cmd
BUNDLE_ID := dev.anton.2cmd
BIN ?= .build/release/$(APP_NAME)
DEPLOY := 15.0
DIST := dist
APP := $(DIST)/$(APP_NAME).app

# TCC pins the Accessibility grant to the app's code identity. An ad-hoc signature
# has no certificate, so the designated requirement collapses to this build's cdhash
# and the grant stops applying after every rebuild (the checkbox stays on and lies).
# Signing with a stable certificate — a self-signed one is enough, no paid Developer
# ID needed — keeps the identity constant so the grant survives rebuilds.
# See README for the one-time certificate setup.
SIGN_IDENTITY ?= 2cmd Local Signing

ICONSET := .build/AppIcon.iconset
ICON := $(DIST)/AppIcon.icns

.PHONY: all build app run install uninstall test lint fmt reset-permission icon signing-cert universal zip dmg release clean

all: app

build:
	swift build -c release

# Universal binary for handing the app to an Intel Mac.
# `swift build --arch` needs xcbuild from full Xcode, which the Command Line Tools
# do not ship — so build each slice by triple and lipo them together.
universal:
	swift build -c release --triple arm64-apple-macosx$(DEPLOY)
	swift build -c release --triple x86_64-apple-macosx$(DEPLOY)
	@mkdir -p .build/universal
	lipo -create -output .build/universal/$(APP_NAME) \
		.build/arm64-apple-macosx/release/$(APP_NAME) \
		.build/x86_64-apple-macosx/release/$(APP_NAME)
	@lipo -archs .build/universal/$(APP_NAME)
	@$(MAKE) app BIN=.build/universal/$(APP_NAME)

# Transferable archive. ditto keeps the signature and bundle structure intact,
# which plain `zip` does not guarantee.
# Deliberately does NOT depend on `app`: that would rebuild the bundle with the
# default single-arch binary and silently discard a universal build.
zip:
	@test -d "$(APP)" || { echo "No $(APP) yet — run 'make app' or 'make universal' first."; exit 1; }
	rm -f "$(DIST)/$(APP_NAME).zip"
	ditto -c -k --keepParent "$(APP)" "$(DIST)/$(APP_NAME).zip"
	@echo "Archive: $(DIST)/$(APP_NAME).zip"

# One command to hand the app to another Mac: universal bundle, then archive.
release: universal
	@$(MAKE) zip

# swift-format ships with the Swift toolchain, so linting needs nothing installed.
lint:
	swift format lint --strict --recursive Sources Tests Tools

fmt:
	swift format --in-place --recursive Sources Tests Tools

# Disk image for people who expect to drag the app into Applications.
# hdiutil is part of macOS; no third-party packaging tool involved.
dmg:
	@test -d "$(APP)" || { echo "No $(APP) yet — run 'make app' or 'make universal' first."; exit 1; }
	rm -rf .build/dmg "$(DIST)/$(APP_NAME).dmg"
	mkdir -p .build/dmg
	cp -R "$(APP)" .build/dmg/
	ln -s /Applications .build/dmg/Applications
	hdiutil create -quiet -volname "$(APP_NAME)" -srcfolder .build/dmg \
		-ov -format UDZO "$(DIST)/$(APP_NAME).dmg"
	@echo "Disk image: $(DIST)/$(APP_NAME).dmg"

# XCTest/swift-testing do not ship with the Command Line Tools, so the state
# machine is checked by a plain executable compiled straight from source.
test:
	@mkdir -p .build
	swiftc -swift-version 5 Sources/TwoCmdCore/*.swift Tests/SoloTapDetectorTests.swift -o .build/solotap-tests
	@.build/solotap-tests

# One-time: create a stable local signing identity so the Accessibility grant
# is not invalidated by every rebuild. See the comment on SIGN_IDENTITY above.
signing-cert:
	@./Tools/make-signing-cert.sh "$(SIGN_IDENTITY)"

# Artwork is generated from source, so no binary blob lives in the repo.
# Rebuilt only when the generator changes.
icon: $(ICON)

$(ICON): Tools/MakeIcon.swift
	@mkdir -p .build "$(DIST)"
	swiftc -swift-version 5 Tools/MakeIcon.swift -o .build/make-icon
	rm -rf "$(ICONSET)"
	@.build/make-icon --iconset "$(ICONSET)"
	iconutil --convert icns "$(ICONSET)" --output "$(ICON)"

app: build $(ICON)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Support/Info.plist "$(APP)/Contents/Info.plist"
	cp "$(ICON)" "$(APP)/Contents/Resources/AppIcon.icns"
	@if security find-identity -p codesigning | grep -q "$(SIGN_IDENTITY)"; then \
		echo "Signing with stable identity: $(SIGN_IDENTITY)"; \
		codesign --force --sign "$(SIGN_IDENTITY)" --identifier "$(BUNDLE_ID)" "$(APP)"; \
	else \
		codesign --force --sign - --identifier "$(BUNDLE_ID)" "$(APP)"; \
		echo "WARNING: ad-hoc signed ('$(SIGN_IDENTITY)' not found in keychain)."; \
		echo "         Accessibility must be re-granted after every rebuild."; \
		echo "         See README to create a reusable signing certificate."; \
	fi
	@echo "Built $(APP)"

run: app
	open "$(APP)"

# Accessibility permission and launch-at-login both want a stable location.
install: app
	pkill -x "$(APP_NAME)" || true
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/
	@echo "Installed /Applications/$(APP_NAME).app"

uninstall:
	pkill -x "$(APP_NAME)" || true
	rm -rf "/Applications/$(APP_NAME).app"

# Clears a stale grant so macOS records the current build and prompts again.
# Toggling the checkbox off/on does NOT do this: it rewrites only the allow bit.
reset-permission:
	tccutil reset Accessibility $(BUNDLE_ID)

clean:
	rm -rf .build "$(DIST)"
