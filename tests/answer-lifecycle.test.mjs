import {test} from 'node:test';import assert from 'node:assert/strict';
import os from 'node:os';
import {mkdtempSync, rmSync} from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {after} from 'node:test';
const testDir=mkdtempSync(os.tmpdir()+'/notch-answer-test-');
const realHomedir=os.homedir;
os.homedir=()=>testDir; syncBuiltinESMExports();
const {Board}=await import('../src/board.ts');
os.homedir=realHomedir; syncBuiltinESMExports();
after(()=>rmSync(testDir,{recursive:true,force:true}));
const session={id:'notch-lifecycle-test',header:{},snapshotEvents:()=>[]};
const ctx={sessions:{list:()=>[session]},agents:{get:()=>({status:'running'})},get:()=>undefined,logger:{warn(){}}};
test('Notch answer cancels the web wait and preserves caller signal',async()=>{
 const board=new Board(ctx), owner=new AbortController();const request={agent:{id:session.id},questions:[{id:'q',question:'test'}],signal:owner.signal};let webVisible=true;
 const pending=board.holdAsk(request,()=>new Promise((resolve,reject)=>{request.signal.addEventListener('abort',()=>{webVisible=false;reject(Error('web wait ended'))},{once:true})}));
 const ask=board.snapshot('http://localhost').rows[0].ask;assert.ok(ask);assert.equal(board.answerAsk(ask.id,[{id:'q',selected:['test']}]),true);
 assert.deepEqual(await pending,{answers:[{id:'q',selected:['test']}]});assert.equal(webVisible,false);assert.equal(owner.signal.aborted,false);assert.equal(request.signal,owner.signal);
});
test('Web answer removes the Notch request',async()=>{
 const board=new Board(ctx);let finish;const answer={answers:[{id:'q',selected:[]}]};
 const pending=board.holdAsk({agent:{id:session.id},questions:[{id:'q',question:'test'}]},()=>new Promise(r=>finish=r));await Promise.resolve();finish(answer);assert.equal(await pending,answer);assert.equal(board.snapshot('http://localhost').rows[0].ask,undefined);
});
