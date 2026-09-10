#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/notch-review.XXXXXX")
cp "$repo/macos/Package.swift" "$work/Package.swift"
cp -R "$repo/macos/Sources" "$work/Sources"
cp "$repo/tools/review/main.swift" "$work/Sources/main.swift"
python3 - "$work/Sources/IdleRobot.swift" <<'PYTHON'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text().replace('final class IdleDirector: ObservableObject {','final class IdleDirector: ObservableObject {\n  static weak var previewInstance: IdleDirector?').replace('  func start(playImmediately: Bool = true) {','  func start(playImmediately: Bool = true) {\n    Self.previewInstance=self');p.write_text(s)
PYTHON
swift build --package-path "$work" -c release -j 2
"$work/.build/release/dsh-notch"
