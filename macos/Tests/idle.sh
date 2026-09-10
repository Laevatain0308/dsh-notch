#!/bin/sh
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/notch-idle.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/Sources"
cp -R "$base/Sources/Resources" "$work/Sources/Resources"
cp "$base/Sources/IdleRobot.swift" "$work/Sources/"
cp "$base/Package.swift" "$work/Package.swift"
cp "$base/Sources/RootView.swift" "$base/Sources/Panel.swift" "$base/Sources/Client.swift" "$base/Sources/StatusOrbit.swift" "$work/Sources/"
cp "$base/Tests/IdleProbe.swift" "$work/Sources/main.swift"
swift build --package-path "$work" -c release
"$work/.build/release/dsh-notch"
