import {homedir} from 'node:os';
import {fileURLToPath,pathToFileURL} from 'node:url';
const {launchPinnedChromium}=await import(pathToFileURL(homedir()+'/.codex/playwright-runtime/runtime.mjs'));
import {writeFile,mkdir} from 'node:fs/promises';
const out=fileURLToPath(new URL('../../macos/Sources/Resources/Idle',import.meta.url));await mkdir(out,{recursive:true});
const b=await launchPinnedChromium();const p=await b.newPage();await p.goto(new URL('./index.html',import.meta.url).href);
await p.evaluate(()=>window.capture=true);
for(const id of ['blink','scan','tilt','nod','stretch','hop','balance','sneeze','sleep','dance']){
 const data=await p.evaluate(id=>{
 const fps=30,duration=id==='dance'?20.783:7,frames=[],proj=new OpenBotMotion.SvgProjector({viewportSize:280});
 const path=document.createElementNS('http://www.w3.org/2000/svg','path');
 for(let i=0;i<Math.ceil(duration*fps);i++){
 const pose=poseFor(id,i/fps).bot,res=proj.projectRoundedCube(pose);path.setAttribute('d',res.bodyPath);const len=path.getTotalLength();
 const points=Array.from({length:64},(_,k)=>{const q=path.getPointAtLength(k*len/64);return [Math.round(q.x*100)/100,Math.round(q.y*100)/100]});
 const eyes=res.eyes.map(e=>({x:e.cx,y:e.cy,w:e.w,h:e.h,r:e.rx,angle:e.angle,opacity:e.opacity??1}));
 frames.push({points,eyes,body:pose.bodyColor,eye:pose.eyeColor});
 }
 return {fps,duration,frames};
 },id);await writeFile(`${out}/${id}.json`,JSON.stringify(data));console.log(id,data.frames.length);
}
await b.close();
