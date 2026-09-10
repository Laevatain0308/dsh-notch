import {appendFileSync, mkdirSync, renameSync, statSync} from 'node:fs'
import {dirname} from 'node:path'
import {freemem,totalmem} from 'node:os'

// Deliberately excludes URLs, page text, tokens and arbitrary error messages.
export function createDiagnosticLog(path, {maxBytes=1024*1024}={}) {
  return (event, data={}) => {
    try {
      mkdirSync(dirname(path),{recursive:true,mode:0o700})
      try {if(statSync(path).size>=maxBytes)renameSync(path,path+'.1')} catch {}
      appendFileSync(path,JSON.stringify({at:new Date().toISOString(),event,...data})+'\n',{mode:0o600})
    } catch {} // Diagnostic failure must never break the shell.
  }
}
export function installRendererDiagnostics({app,contents,write,related=()=>({}),intervalMs=30000}) {
  const disposers=[]
  const on=(emitter,event,fn)=>{emitter.on(event,fn);disposers.push(()=>emitter.removeListener(event,fn))}
  const snapshot=()=>{
    let processes=[]
    try {processes=app.getAppMetrics().map(p=>({pid:p.pid,type:p.type,cpu:p.cpu?.percentCPUUsage,rssKB:p.memory?.workingSetSize,peakKB:p.memory?.peakWorkingSetSize}))}catch{}
    let rendererPid=null
    try{rendererPid=contents.getOSProcessId()}catch{}
    return {appPid:process.pid,contentsId:contents.id,rendererPid,processes,freeMemoryBytes:freemem(),totalMemoryBytes:totalmem(),...related()}
  }
  const record=(event,data={})=>{try{write(event,{...snapshot(),...data})}catch{}}
  on(contents,'render-process-gone',(_event,details)=>record('renderer-exited',{reason:details.reason,exitCode:details.exitCode}))
  on(contents,'unresponsive',()=>record('renderer-unresponsive'))
  on(contents,'responsive',()=>record('renderer-responsive'))
  on(contents,'did-start-loading',()=>record('page-loading'))
  on(contents,'did-finish-load',()=>record('page-loaded'))
  on(contents,'did-fail-load',(_event,errorCode,_description,_url,isMainFrame)=>record('page-load-failed',{errorCode,isMainFrame}))
  on(app,'child-process-gone',(_event,details)=>record('child-exited',{type:details.type,reason:details.reason,exitCode:details.exitCode}))
  const timer=setInterval(()=>record('heartbeat'),intervalMs);timer.unref?.()
  let disposed=false
  function dispose(){if(disposed)return;disposed=true;clearInterval(timer);for(const fn of disposers)fn()}
  on(contents,'destroyed',()=>{record('contents-destroyed');dispose()})
  record('diagnostics-attached')
  return dispose
}
