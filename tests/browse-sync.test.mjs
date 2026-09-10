import {test} from 'node:test'
import assert from 'node:assert/strict'
import {installBrowseSync} from '../src/browse-sync.ts'
class Controller { history={page:async()=>({records:[1]}),follow:async function*(){yield {records:[1]}}}; page(request,signal){return this.history.page(request,signal)} follow(request,signal){return this.history.follow(request,signal)} }
const req={address:{sessionId:'test'}}
test('legacy synchronous Notch wrapper reproduces exact error; repair removes all nested wrappers',async()=>{
 const c=new Controller();const board={markSeen(){}};const getTargetSessionId=a=>a.sessionId
 for(let i=0;i<2;i++){const origFollow=c.follow.bind(c);c.follow=function* (req, signal) {const sid=getTargetSessionId(req.address);if(sid)board.markSeen(sid);return yield* origFollow(req,signal)}}
 await assert.rejects(async()=>{for await(const x of c.follow(req)){}},/is not iterable/)
 const stop=installBrowseSync(c,()=>{});const rows=[];for await(const x of c.follow(req))rows.push(x)
 assert.deepEqual(rows,[{records:[1]}]);stop();assert.equal(Object.hasOwn(c,'follow'),false)
})
test('preserves async stream identity, return, cancellation; repeated generations dispose cleanly',async()=>{
 const c=new Controller();let returned=0;const signal=AbortSignal.abort();const source={async *[Symbol.asyncIterator](){try{yield 1;yield 2}finally{returned++}}}
 c.history.follow=(r,s)=>{assert.equal(s,signal);return source}
 let a=0,b=0;const stopA=installBrowseSync(c,()=>a++);const stopB=installBrowseSync(c,()=>b++)
 assert.equal(c.follow(req,signal),source);stopA();const stream=c.follow(req,signal);for await(const v of stream){break}
 assert.equal(a,1);assert.equal(b,2);assert.equal(returned,1);stopB();stopB();assert.equal(Object.hasOwn(c,'follow'),false)
 const stop=installBrowseSync(c,()=>{throw Error('read marker failed')});assert.deepEqual(await c.page(req),{records:[1]});stop()
})
