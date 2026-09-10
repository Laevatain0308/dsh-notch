#!/usr/bin/env python3
"""Stage a reviewed thin-shell patch. Never installs or restarts DSH."""
from pathlib import Path
import argparse, hashlib, json, struct
p=argparse.ArgumentParser();p.add_argument('archive',type=Path);p.add_argument('output',type=Path);args=p.parse_args()
raw=args.archive.read_bytes();hs=struct.unpack_from('<I',raw,4)[0];js=struct.unpack_from('<I',raw,12)[0]
tree=json.loads(raw[16:16+js]);files={}
def walk(entries,prefix=''):
 for name,e in entries.items():
  key=prefix+name
  if 'files' in e:walk(e['files'],key+'/')
  else:
   assert not e.get('unpacked') and 'link' not in e, 'unsupported archive entry'
   start=8+hs+int(e['offset']);files[key]=raw[start:start+e['size']]
walk(tree['files'])
original=dict(files);source=files['src/main.mjs'].decode()
assert 'installRendererRecovery' not in source, 'recovery already installed; use the preserved base archive'
def replace(old,new):
 global source
 assert source.count(old)==1, 'unexpected shell source: '+old[:70]
 source=source.replace(old,new,1)
replace("import { createDiagnosticLog, installRendererDiagnostics }", "import { pipeChildLog } from './child-log.mjs'\nimport { installRendererRecovery } from './renderer-recovery.mjs'\nimport { createDiagnosticLog, installRendererDiagnostics }")
replace('const { app, BrowserWindow, Menu, clipboard, session, shell, systemPreferences } = electron','const { app, BrowserWindow, Menu, clipboard, session, shell, systemPreferences, powerMonitor, dialog } = electron')
replace('''  const attachDiagnostics = contents => installRendererDiagnostics({
    app, contents, write: diagnosticWrite,
    related: () => ({hostPid: sidecar?.pid ?? null, notchPid: notch?.pid ?? null}),
  })''','''  const attachDiagnostics = contents => {
    const owner = BrowserWindow.fromWebContents(contents)
    installRendererDiagnostics({
      app, contents, window: owner, powerMonitor, write: diagnosticWrite,
      related: () => ({hostPid: sidecar?.pid ?? null, notchPid: notch?.pid ?? null}),
    })
    let promptOpen = false
    installRendererRecovery({
      app, window: owner, write: diagnosticWrite,
      onUnavailable: async () => {
        if (promptOpen || owner.isDestroyed()) return
        promptOpen = true
        try {
          const result = await dialog.showMessageBox(owner, {
            type: 'error', title: 'DSH 页面未能恢复',
            message: '页面连续异常退出或重新加载超时。',
            detail: '后台服务没有因页面恢复而重启。可以重新加载页面，或稍后从 View → Reload 重试。',
            buttons: ['重新加载页面', '稍后'], defaultId: 0, cancelId: 1, noLink: true,
          })
          if (result.response === 0 && !owner.isDestroyed()) contents.reload()
        } finally { promptOpen = false }
      },
    })
  }''')
pair="  child.stdout?.pipe(log)\n  child.stderr?.pipe(log)"
assert source.count(pair)==2
source=source.replace(pair, '  pipeChildLog(child, log)')
replace("  return log\n}", "  log.on('error', () => {}) // Logging failure must not crash the desktop shell.\n  return log\n}")
root=Path(__file__).parent
files['src/child-log.mjs']=(root/'child-log.mjs').read_bytes()
files['src/main.mjs']=source.encode()
files['src/renderer-recovery.mjs']=(root/'renderer-recovery.mjs').read_bytes()
files['src/renderer-diagnostics.mjs']=(root.parent/'diagnostics/renderer-diagnostics.mjs').read_bytes()
header={'files':{}};payload=bytearray()
for name,body in files.items():
 node=header['files'];parts=name.split('/')
 for part in parts[:-1]:node=node.setdefault(part,{'files':{}})['files']
 digest=hashlib.sha256(body).hexdigest()
 node[parts[-1]]={'size':len(body),'offset':str(len(payload)),'integrity':{'algorithm':'SHA256','hash':digest,'blockSize':4194304,'blocks':[hashlib.sha256(body[i:i+4194304]).hexdigest() for i in range(0,len(body),4194304)]}}
 payload.extend(body)
encoded=json.dumps(header,separators=(',',':')).encode();body=struct.pack('<I',len(encoded))+encoded;body+=b'\0'*((-len(body))%4);pickle=struct.pack('<I',len(body))+body
archive=struct.pack('<II',4,len(pickle))+pickle+payload
args.output.mkdir(parents=True,exist_ok=True)
(args.output/'app.asar').write_bytes(archive)
(args.output/'main.mjs').write_text(source)
new_hs=struct.unpack_from('<I',archive,4)[0]
for name,expected in files.items():
 node=header['files']
 for part in name.split('/')[:-1]:node=node[part]['files']
 e=node[name.split('/')[-1]];start=8+new_hs+int(e['offset']);assert archive[start:start+e['size']]==expected
manifest={'inputSHA256':hashlib.sha256(raw).hexdigest(),'outputSHA256':hashlib.sha256(archive).hexdigest(),'changed':[n for n,b in files.items() if original.get(n)!=b]}
(args.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(manifest))
