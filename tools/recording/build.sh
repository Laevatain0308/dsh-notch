#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
work="$repo/.build/recording"
mkdir -p "$work/Sources" "$repo/dist"
python3 - "$repo" "$work" <<'PY'
from pathlib import Path
import shutil,sys
repo,work=map(Path,sys.argv[1:])
# Every island source except the ones that belong to the application: the demo is
# its own program with its own entry point and its own windows.
skip={'DshNotchMain.swift','MotionBrowser.swift','SettingsWindow.swift','ReviewStudio.swift'}
for path in sorted((repo/'macos/Sources').glob('*.swift')):
    if path.name not in skip:
        shutil.copy2(path,work/'Sources'/path.name)
shutil.copy2(repo/'macos/Sources/Client.swift',work/'Sources/Client.swift')
# The island's own client, so the demo asks for the same things the island does.
for name in ['DemoCatalog.swift','MotionCatalog.swift']:
    shutil.copy2(repo/'tools/recording'/name,work/'Sources'/name)
# A file named main.swift is top-level code, which forbids the `@main` the
# recording entry declares; the copy keeps a name that allows it.
shutil.copy2(repo/'tools/recording/main.swift',work/'Sources/RecordingMain.swift')
shutil.copytree(repo/'macos/Sources/Resources',work/'Sources/Resources',dirs_exist_ok=True)
p=work/'Sources/IdleRobot.swift';s=p.read_text()
old='.onAppear { presence.set(idle, director: director, animated: false) }'
new='''.onAppear { director.automaticActions=false;presence.set(idle, director: director, animated: false) }
    .onReceive(NotificationCenter.default.publisher(for:PreviewIdleCue.notification)) { note in
      guard let cue=note.object as? PreviewIdleCue,cue.boardID==ObjectIdentifier(model) else {return}
      director.automaticActions=false;director.play(cue.action)
    }'''
assert s.count(old)==1,'Idle playback hook changed; inspect the production source before updating this adapter.'
p.write_text(s.replace(old,new))
(work/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name:"NotchDemo",platforms:[.macOS(.v14)],products:[.executable(name:"NotchDemo",targets:["NotchDemo"])],targets:[.executableTarget(name:"NotchDemo",path:"Sources",resources:[.copy("Resources/Idle")])])
''')
PY
swift build --package-path "$work" -c release
python3 - "$repo" "$work" <<'PY'
from pathlib import Path
import shutil,plistlib,sys
repo,work=map(Path,sys.argv[1:]);app=repo/'dist/DSH Notch Demo.app/Contents'
(app/'MacOS').mkdir(parents=True,exist_ok=True);(app/'Resources').mkdir(exist_ok=True)
shutil.copy2(work/'.build/release/NotchDemo',app/'MacOS/NotchDemo')
for bundle in (work/'.build/release').glob('*.bundle'):
    shutil.copytree(bundle,app/'Resources'/bundle.name,dirs_exist_ok=True)
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.dsh.notch.demo','CFBundleName':'DSH Notch Demo','CFBundleExecutable':'NotchDemo','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.3.0','CFBundleVersion':'3','NSHighResolutionCapable':True,'LSMinimumSystemVersion':'14.0'}))
print(app.parent)
PY
