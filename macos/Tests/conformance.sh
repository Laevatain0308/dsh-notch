#!/bin/sh
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/notch-conformance.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/Sources"
cp -R "$base/Sources/Resources" "$work/Sources/Resources"
cp "$base/Package.swift" "$work/Package.swift"
cp "$base/Sources/Protocol.swift" "$base/Sources/ProviderSession.swift" "$base/Sources/NotchCore.swift" "$work/Sources/"
cp "$base/Tests/ConformanceProbe.swift" "$work/Sources/Probe.swift"
swift build --package-path "$work" -c release
"$work/.build/release/dsh-notch" "$base/../protocol/v1/conformance.json"
