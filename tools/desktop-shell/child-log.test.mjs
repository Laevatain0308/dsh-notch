import {test} from 'node:test';import assert from 'node:assert/strict';import {PassThrough} from 'node:stream';
import {pipeChildLog} from './child-log.mjs';
test('child EOF leaves shared log open for exit callback and other child',async()=>{
 const log=new PassThrough(),chunks=[],errors=[];log.on('data',c=>chunks.push(c.toString()));log.on('error',e=>errors.push(e));
 const first={stdout:new PassThrough(),stderr:new PassThrough()},second={stdout:new PassThrough(),stderr:new PassThrough()};
 pipeChildLog(first,log);pipeChildLog(second,log);
 first.stdout.end('first-out\n');first.stderr.end('first-err\n');
 await new Promise(setImmediate);
 assert.equal(log.writableEnded,false);
 log.write('first-exit\n');second.stdout.end('second-out\n');second.stderr.end('second-err\n');
 await new Promise(setImmediate);
 log.write('second-exit\n');await new Promise(setImmediate);
 assert.equal(errors.length,0);assert.match(chunks.join(''),/first-exit/);assert.match(chunks.join(''),/second-exit/);log.end();
});
