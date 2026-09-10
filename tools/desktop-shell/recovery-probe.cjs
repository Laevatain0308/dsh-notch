// Native integration test: isolated profile/static fixture, never the user's DSH.
const {app,BrowserWindow}=require('electron');
const assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {pathToFileURL}=require('node:url');
const profile=fs.mkdtempSync(path.join(os.tmpdir(),'dsh-recovery-test-'));
app.setPath('userData',profile);app.setPath('sessionData',profile);
app.on('window-all-closed',()=>{});
const nativePid=process.pid;
const waitFor=(emitter,event)=>new Promise(resolve=>emitter.once(event,resolve));
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const deadline=setTimeout(()=>{console.error('native recovery timeout');app.exit(2)},20000);
app.whenReady().then(async()=>{
 const {installRendererRecovery}=await import(pathToFileURL(process.env.DSH_RECOVERY_MODULE||path.join(__dirname,'renderer-recovery.mjs')));
 const results=[];
 for(const hidden of [false,true]){
  const events=[];let unavailable=0;
  const window=new BrowserWindow({width:460,height:220,show:false,webPreferences:{sandbox:true,contextIsolation:true,nodeIntegration:false}});
  const wc=window.webContents;
  let complete;
  if(!process.argv.includes('--baseline'))installRendererRecovery({app,window,write:(event,data)=>{events.push({event,...data});if(event==='renderer-recovery-complete')complete?.()},onUnavailable:()=>unavailable++});
  await window.loadURL('data:text/html,<title>DSH recovery fixture</title><body style="margin:0;background:%23004c2e;color:white;font:24px sans-serif;padding:32px"><h1>Recovery fixture</h1><p>Local static page. No model calls.</p></body>');
  if(!hidden)window.showInactive();
  const originalContents=wc.id;
  const baselinePixels=(await wc.capturePage()).toBitmap();
  const reference=Array.from(baselinePixels.subarray(0,4));
  assert.ok(reference[1]>reference[0]&&reference[1]>reference[2]&&reference[3]>0,'baseline fixture must be green');
  for(let cycle=1;cycle<=2;cycle++){
   const oldPid=wc.getOSProcessId();
   const recovered=new Promise(resolve=>{complete=resolve});
   const gone=waitFor(wc,'render-process-gone');
   wc.forcefullyCrashRenderer();
   await gone;
   if(process.argv.includes('--baseline')){await delay(700);assert.ok(wc.getOSProcessId()>0,'renderer remains dead: persistent blank window after exit');}
   await recovered;
   assert.equal(process.pid,nativePid);assert.equal(wc.id,originalContents);
   assert.ok(wc.getOSProcessId()>0);assert.notEqual(wc.getOSProcessId(),oldPid);
   assert.equal(await wc.executeJavaScript('document.querySelector("h1").textContent'),'Recovery fixture');
   const frame=await wc.capturePage();const pixels=frame.toBitmap();
   let green=0;for(let i=0;i<pixels.length;i+=4)if(reference.every((v,j)=>Math.abs(pixels[i+j]-v)<=3))green++;
   assert.ok(green>pixels.length/4*.5,'recovered page must paint fixture background instead of white');
   results.push({hidden,cycle,recovered:true,sameContents:true,painted:true});
  }
  const gone=waitFor(wc,'render-process-gone');wc.forcefullyCrashRenderer();await gone;await delay(400);
  assert.equal(unavailable,1,'third rapid exit must stop auto reload');
  window.destroy();
 }
 console.log(JSON.stringify({electron:process.versions.electron,results,boundedRetry:true}));
 clearTimeout(deadline);app.exit(0);
}).catch(error=>{console.error(error.stack);clearTimeout(deadline);app.exit(1)});
