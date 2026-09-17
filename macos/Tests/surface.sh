#!/bin/sh
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/notch-surface.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/Sources"
cp -R "$base/Sources/Resources" "$work/Sources/Resources"
cp "$base/Package.swift" "$work/Package.swift"
cp "$base/Sources/Protocol.swift" "$base/Sources/ProviderSession.swift" "$base/Sources/NotchCore.swift" "$base/Sources/ConsentPrompt.swift" "$base/Sources/Surface.swift" "$base/Sources/Identity.swift" "$base/Sources/Consent.swift" "$work/Sources/"
cp "$base/Tests/SurfaceProbe.swift" "$work/Sources/Probe.swift"
swift build --package-path "$work" -c release
"$work/.build/release/dsh-notch"
