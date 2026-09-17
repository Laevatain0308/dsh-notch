#!/bin/sh
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work="$base/.build/scrollbar-probe"
mkdir -p "$work/Sources"
cp -R "$base/Sources/Resources" "$work/Sources/"
cp "$base/Package.swift" "$work/Package.swift"
# This work directory is reused across runs, unlike the mktemp ones. Drop an
# earlier entry file, or the renamed copy is compiled next to it and the probe
# type is declared twice.
rm -f "$work/Sources/main.swift" "$work/Sources/Probe.swift"
for file in Protocol.swift ConsentPrompt.swift IdleRobot.swift NotchMarkdown.swift ConsentView.swift RootView.swift Panel.swift Client.swift StatusOrbit.swift; do
  cp "$base/Sources/$file" "$work/Sources/$file"
done
cp "$base/Tests/ScrollbarProbe.swift" "$work/Sources/Probe.swift"
swift build --package-path "$work" -c release
"$work/.build/release/dsh-notch"
