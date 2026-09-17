#!/bin/sh
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/notch-outcome.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/Sources"
cp -R "$base/Sources/Resources" "$work/Sources/Resources"
cp "$base/Sources/AppResources.swift" "$base/Sources/IdleRobot.swift" "$work/Sources/"
cp "$base/Sources/NotchMarkdown.swift" "$work/Sources/"
cp "$base/Package.swift" "$work/Package.swift"
cp "$base/Sources/Surface.swift" "$base/Sources/MotionLibrary.swift" "$base/Sources/SurfaceView.swift" "$base/Sources/NotchCore.swift" "$base/Sources/ProviderSession.swift" "$base/Sources/Consent.swift" "$base/Sources/Identity.swift" "$base/Sources/Endpoint.swift" "$base/Sources/NotchService.swift" "$base/Sources/Protocol.swift" "$base/Sources/ConsentPrompt.swift" "$base/Sources/ConsentView.swift" "$base/Sources/RootView.swift" "$base/Sources/Panel.swift" "$base/Sources/Client.swift" "$base/Sources/StatusOrbit.swift" "$work/Sources/"
cp "$base/Tests/OutcomeProbe.swift" "$work/Sources/Probe.swift"
swift build --package-path "$work" -c release
"$work/.build/release/dsh-notch"
