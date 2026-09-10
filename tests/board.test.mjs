import {test} from 'node:test'
import assert from 'node:assert/strict'
import {Board} from '../src/board.ts'
const session={id:'session-regression',header:{},snapshotEvents:()=>[]}
const ctx={sessions:{list:()=>[session]},agents:{get:()=>({status:'running'})},get:()=>undefined,logger:{warn:()=>{}}}
test('snapshot and background notification handle live sessions without missing seen state',()=>{const board=new Board(ctx);let notifications=0;board.onChange(()=>{assert.equal(board.snapshot('http://localhost').rows.length,1);notifications++});board.notify();assert.equal(notifications,1)})
test('one broken subscriber cannot crash Host or stop other subscribers',()=>{const board=new Board(ctx);let n=0;board.onChange(()=>{throw Error('broken stream')});board.onChange(()=>n++);assert.doesNotThrow(()=>board.notify());assert.equal(n,1)})
