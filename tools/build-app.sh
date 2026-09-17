#!/bin/sh
#
# Package the overlay as an application.
#
# The overlay is a normal macOS application: it is started by the user, it keeps
# its own resources, and it has a bundle identifier so that the identity consent
# is pinned to is a name the user can be shown rather than a path in a build
# directory. `swift build` produces an executable, which is enough to develop
# against and not enough to be run as an application — this is the difference.
#
# Usage: tools/build-app.sh [output directory]
#
set -eu

base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=${1:-"$base/dist"}
config=${CONFIG:-release}
name=${APP_NAME:-Notch}
identifier=${APP_IDENTIFIER:-com.github.laevatain0308.notch}
version=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$base/package.json" | head -1)
version=${version:-0.0.0}

app="$out/$name.app"
binary="$base/macos/.build/$config/dsh-notch"
resources="$base/macos/.build/$config/DshNotch_DshNotch.bundle"

if [ ! -x "$binary" ]; then
  echo "build-app: no executable at $binary; run: npm run build:macos" >&2
  exit 1
fi
if [ ! -d "$resources" ]; then
  echo "build-app: no resource bundle at $resources; run: npm run build:macos" >&2
  exit 1
fi

# Assembled from scratch every time: a stale file inside an application is a
# difference between what was built and what runs, which is the one thing a
# package must not have.
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

# The executable is named for the application, because that name is what the
# consent surface shows the user when this program asks to speak.
cp "$binary" "$app/Contents/MacOS/$name"
cp -R "$resources" "$app/Contents/Resources/$(basename "$resources")"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>$name</string>
	<key>CFBundleDisplayName</key>
	<string>$name</string>
	<key>CFBundleExecutable</key>
	<string>$name</string>
	<key>CFBundleIdentifier</key>
	<string>$identifier</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$version</string>
	<key>CFBundleVersion</key>
	<string>$version</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<!-- An accessory: it has no Dock icon and no menu bar of its own, because it
	     is a surface other programs are shown on rather than an application the
	     user switches to. -->
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<!-- The overlay stops itself on a Host's shutdown and must not be terminated
	     by the system when it looks idle, which it always does. -->
	<key>NSSupportsAutomaticTermination</key>
	<false/>
	<key>NSSupportsSuddenTermination</key>
	<false/>
</dict>
</plist>
PLIST

# Signed ad hoc by default, which is what makes the bundle's identity stable
# enough for consent to be pinned to it. A real identity can be given instead:
#   APP_SIGN_IDENTITY="Developer ID Application: …" tools/build-app.sh
identity=${APP_SIGN_IDENTITY:--}
codesign --force --deep --sign "$identity" --identifier "$identifier" "$app" 2>&1 | sed 's/^/build-app: /'

echo "build-app: $app"
echo "build-app: $(codesign -dvvv "$app" 2>&1 | grep -E '^Identifier|^CDHash' | tr '\n' ' ')"
