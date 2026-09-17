#!/bin/sh
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/notch-consent.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/Sources"
cp -R "$base/Sources/Resources" "$work/Sources/Resources"
cp "$base/Package.swift" "$work/Package.swift"
cp "$base/Sources/Protocol.swift" "$base/Sources/ProviderSession.swift" "$base/Sources/NotchCore.swift" "$base/Sources/Consent.swift" "$base/Sources/Endpoint.swift" "$work/Sources/"
cp "$base/Tests/ConsentProbe.swift" "$work/Sources/Probe.swift"
swift build --package-path "$work" -c release
"$work/.build/release/dsh-notch"
