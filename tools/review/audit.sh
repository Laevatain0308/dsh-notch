#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/notch-audit.XXXXXX")
output=${1:-"$work/frames"}
mkdir -p "$output"
cp "$repo/macos/Package.swift" "$work/Package.swift"
cp -R "$repo/macos/Sources" "$work/Sources"
python3 - "$repo" "$work" <<'PYTHON'
from pathlib import Path
import sys
repo,work=map(Path,sys.argv[1:])
s=(repo/'tools/review/main.swift').read_text().split('@main enum LoopMain')[0]
s+=(repo/'tools/review/render-audit.swift').read_text()
(work/'Sources/main.swift').write_text(s)
p=work/'Sources/IdleRobot.swift';s=p.read_text().replace('final class IdleDirector: ObservableObject {','final class IdleDirector: ObservableObject {\n  static weak var previewInstance: IdleDirector?').replace('  func start(playImmediately: Bool = true) {','  func start(playImmediately: Bool = true) {\n    Self.previewInstance=self');p.write_text(s)
PYTHON
swift build --package-path "$work" -c release -j 2
NOTCH_AUDIT_OUTPUT="$output" "$work/.build/release/dsh-notch"
