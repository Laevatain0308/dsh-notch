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
export function installRendererDiagnostics({app,contents,window,powerMonitor,write,related=()=>({}),intervalMs=30000}) {
  const disposers=[]
  const on=(emitter,event,fn)=>{emitter.on(event,fn);disposers.push(()=>emitter.removeListener(event,fn))}
  let lastRendererPid=null, loadedAt=null
  const read=(object,method)=>{try{return object?.[method]?.()}catch{return undefined}}
  const snapshot=()=>{
    let processes=[]
    try {processes=app.getAppMetrics().map(p=>({pid:p.pid,type:p.type,cpu:p.cpu?.percentCPUUsage,rssKB:p.memory?.workingSetSize,peakKB:p.memory?.peakWorkingSetSize}))}catch{}
    let rendererPid=null
    try{rendererPid=contents.getOSProcessId()}catch{}
    if(rendererPid>0)lastRendererPid=rendererPid
    return {appPid:process.pid,contentsId:contents.id,rendererPid,lastRendererPid,
      pageAgeMs:loadedAt===null?null:Date.now()-loadedAt,
      systemIdleSeconds:read(powerMonitor,'getSystemIdleTime'),
      windowVisible:read(window,'isVisible'),windowMinimized:read(window,'isMinimized'),
      windowFocused:read(window,'isFocused'),appHidden:read(app,'isHidden'),
      loading:read(contents,'isLoading'),backgroundThrottling:read(contents,'getBackgroundThrottling'),
      processes,freeMemoryBytes:freemem(),totalMemoryBytes:totalmem(),...related()}
  }
  const record=(event,data={})=>{try{write(event,{...snapshot(),...data})}catch{}}
  on(contents,'render-process-gone',(_event,details)=>record('renderer-exited',{reason:details.reason,exitCode:details.exitCode}))
  on(contents,'unresponsive',()=>record('renderer-unresponsive'))
  on(contents,'responsive',()=>record('renderer-responsive'))
  on(contents,'did-start-loading',()=>record('page-loading'))
  on(contents,'did-finish-load',()=>{loadedAt=Date.now();record('page-loaded')})
  on(contents,'did-fail-load',(_event,errorCode,_description,_url,isMainFrame)=>record('page-load-failed',{errorCode,isMainFrame}))
  on(app,'child-process-gone',(_event,details)=>record('child-exited',{type:details.type,reason:details.reason,exitCode:details.exitCode}))
  // No URLs, navigation arguments, input text or session content are recorded.
  for(const event of ['render-view-deleted','render-view-ready','dom-ready','will-prevent-unload'])
    on(contents,event,()=>record(event))
  if(window)for(const event of ['show','hide','minimize','restore','focus','blur','resize','close','closed'])
    on(window,event,()=>record('window-'+event))
  if(powerMonitor)for(const event of ['suspend','resume','lock-screen','unlock-screen'])
    on(powerMonitor,event,()=>record('system-'+event))
  on(app,'before-quit',()=>record('app-before-quit'))
  const timer=setInterval(()=>record('heartbeat'),intervalMs);timer.unref?.()
  let disposed=false
  function dispose(){if(disposed)return;disposed=true;clearInterval(timer);for(const fn of disposers)fn()}
  on(contents,'destroyed',()=>{record('contents-destroyed');dispose()})
  record('diagnostics-attached')
  return dispose
}
