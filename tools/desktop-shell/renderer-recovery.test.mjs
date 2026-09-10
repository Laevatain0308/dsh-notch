import {test} from 'node:test'
import assert from 'node:assert/strict'
import {EventEmitter} from 'node:events'
import {installRendererRecovery} from './renderer-recovery.mjs'

function fixture(options={}) {
 const app=new EventEmitter(),window=new EventEmitter(),contents=new EventEmitter(),rows=[],failures=[];
 let reloaded=0,destroyed=false,pid=17,loading=false,clock=0,seq=0;
 const jobs=new Map();
 window.webContents=contents;window.isDestroyed=()=>destroyed;
 contents.isDestroyed=()=>destroyed;contents.getOSProcessId=()=>pid;
 contents.isLoading=()=>loading;contents.reload=()=>{reloaded++;loading=true;contents.emit('did-start-loading')};
 const scheduler={setTimeout:(fn,ms)=>{const id=++seq;jobs.set(id,{fn,at:clock+ms});return id},clearTimeout:id=>jobs.delete(id)};
 const dispose=installRendererRecovery({app,window,write:(event,data)=>rows.push({event,...data}),onUnavailable:reason=>failures.push(reason),repaint:()=>rows.push({event:'repaint'}),now:()=>clock,scheduler,...options});
 const tick=ms=>{const end=clock+ms;while(true){const ready=[...jobs].filter(([,j])=>j.at<=end).sort((a,b)=>a[1].at-b[1].at)[0];if(!ready)break;clock=ready[1].at;jobs.delete(ready[0]);ready[1].fn()}clock=end};
 return {app,window,contents,rows,failures,dispose,tick,jobs,get reloads(){return reloaded},gone(reason='clean-exit'){pid=0;loading=false;contents.emit('render-process-gone',{}, {reason,exitCode:0,url:'private-token'})},loaded(){pid=18;loading=false;contents.emit('did-finish-load')},destroy(){destroyed=true;window.emit('closed')}}
}
test('unexpected clean exit reloads original contents and completes recovery',()=>{const f=fixture();f.gone();f.tick(300);assert.equal(f.reloads,1);f.loaded();assert.equal(f.rows.at(-1).event,'renderer-recovery-complete');assert.ok(f.rows.some(r=>r.event==='repaint'));assert.ok(!JSON.stringify(f.rows).includes('private-token'));f.dispose()})
test('duplicate exit before scheduled reload does not consume another attempt',()=>{const f=fixture();f.gone();f.gone();f.tick(300);assert.equal(f.reloads,1);f.loaded();f.dispose()})
test('normal quit and closed windows never resurrect a renderer',()=>{for(const stop of [f=>f.app.emit('before-quit'),f=>f.destroy()]){const f=fixture();f.gone();stop(f);f.tick(20000);assert.equal(f.reloads,0);f.dispose()}})
test('crash loop is bounded, including repeated clean exits',()=>{const f=fixture();for(let i=0;i<3;i++){f.gone();f.tick(300);f.loaded()}assert.equal(f.reloads,2);assert.equal(f.failures.length,1);f.tick(60000);f.gone();f.tick(300);assert.equal(f.reloads,3);f.dispose()})
test('manual reload wins over queued automatic recovery',()=>{const f=fixture();f.gone();f.contents.reload();f.loaded();f.tick(20000);assert.equal(f.reloads,1);assert.equal(f.failures.length,0);f.dispose()})
test('load timeout is reported once; late load may still recover',()=>{const f=fixture();f.gone();f.tick(20000);assert.equal(f.reloads,1);assert.deepEqual(f.failures,['load-timeout']);f.loaded();assert.equal(f.rows.at(-1).event,'renderer-recovery-complete');f.dispose()})
test('disposal cancels work and removes all owned listeners',()=>{const f=fixture();f.gone();f.dispose();f.tick(20000);assert.equal(f.reloads,0);assert.equal(f.jobs.size,0);assert.equal(f.contents.listenerCount('render-process-gone'),0);assert.equal(f.app.listenerCount('before-quit'),0)})
