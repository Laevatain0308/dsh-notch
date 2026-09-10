import {test} from 'node:test';import assert from 'node:assert/strict';import {EventEmitter} from 'node:events';
import {mkdtempSync,readFileSync,rmSync,existsSync} from 'node:fs';import {tmpdir} from 'node:os';
import {createDiagnosticLog,installRendererDiagnostics} from './renderer-diagnostics.mjs';
function fixture(){const app=new EventEmitter(),contents=new EventEmitter();app.getAppMetrics=()=>[{pid:7,type:'Tab',memory:{workingSetSize:123}}];contents.id=3;contents.getOSProcessId=()=>7;return {app,contents}}
test('renderer termination retains reason and exit code, strips secrets',()=>{const f=fixture(),rows=[];const dispose=installRendererDiagnostics({...f,write:(event,data)=>rows.push({event,...data})});f.contents.emit('render-process-gone',{}, {reason:'oom',exitCode:137,url:'secret',message:'secret'});const row=rows.at(-1);assert.equal(row.event,'renderer-exited');assert.equal(row.reason,'oom');assert.equal(row.exitCode,137);assert.equal(row.rendererPid,7);assert.ok(!JSON.stringify(rows).includes('secret'));dispose();assert.equal(f.contents.listenerCount('render-process-gone'),0)})
test('secondary process and loading events exclude URLs and messages',()=>{const f=fixture(),rows=[];const dispose=installRendererDiagnostics({...f,write:(e,d)=>rows.push({e,...d})});f.contents.emit('did-fail-load',{},-2,'secret','token-url',true);f.app.emit('child-process-gone',{}, {type:'GPU',reason:'crashed',exitCode:1,name:'secret'});assert.equal(rows.at(-1).type,'GPU');assert.ok(!JSON.stringify(rows).includes('secret'));assert.ok(!JSON.stringify(rows).includes('token-url'));dispose()})
test('diagnostic errors cannot break shell, destruction cleans up',()=>{const f=fixture();installRendererDiagnostics({...f,write:()=>{throw Error('disk full')}});assert.doesNotThrow(()=>f.contents.emit('render-process-gone',{}, {reason:'crashed',exitCode:1}));f.contents.emit('destroyed');assert.equal(f.app.listenerCount('child-process-gone'),0)})
test('rotates log at limit',()=>{const dir=mkdtempSync(tmpdir()+'/notch-diag-');try{const path=dir+'/events.jsonl',write=createDiagnosticLog(path,{maxBytes:1});write('one');write('two');assert.ok(existsSync(path+'.1'));assert.equal(JSON.parse(readFileSync(path,'utf8')).event,'two')}finally{rmSync(dir,{recursive:true,force:true})}})
test('idle renderer loss preserves departed PID and window state without private event arguments',()=>{
  const f=fixture(),window=new EventEmitter(),powerMonitor=new EventEmitter(),rows=[];
  window.isVisible=()=>true;window.isMinimized=()=>false;window.isFocused=()=>false;
  powerMonitor.getSystemIdleTime=()=>7200;
  const dispose=installRendererDiagnostics({...f,window,powerMonitor,write:(event,data)=>rows.push({event,...data})});
  f.contents.emit('did-finish-load');
  f.contents.getOSProcessId=()=>0;
  f.contents.emit('render-process-gone',{}, {reason:'clean-exit',exitCode:0});
  const row=rows.at(-1);
  assert.equal(row.rendererPid,0);assert.equal(row.lastRendererPid,7);
  assert.equal(row.systemIdleSeconds,7200);assert.equal(row.windowFocused,false);
  assert.ok(row.pageAgeMs>=0);
  powerMonitor.emit('suspend','private');window.emit('hide','private');
  assert.equal(rows.at(-2).event,'system-suspend');assert.equal(rows.at(-1).event,'window-hide');
  assert.ok(!JSON.stringify(rows).includes('private'));
  dispose();assert.equal(window.listenerCount('hide'),0);assert.equal(powerMonitor.listenerCount('suspend'),0);
});
test('unsupported or destroyed window and power APIs do not break remaining evidence',()=>{
  const f=fixture(),window=new EventEmitter(),powerMonitor=new EventEmitter(),rows=[];
  window.isVisible=()=>{throw Error('destroyed')};powerMonitor.getSystemIdleTime=()=>{throw Error('unsupported')};
  const dispose=installRendererDiagnostics({...f,window,powerMonitor,write:(event,data)=>rows.push({event,...data})});
  f.contents.emit('render-process-gone',{}, {reason:'killed',exitCode:15});
  assert.equal(rows.at(-1).reason,'killed');assert.equal(rows.at(-1).systemIdleSeconds,undefined);dispose();
});
