import {homedir} from 'node:os';
import {fileURLToPath,pathToFileURL} from 'node:url';
const {launchPinnedChromium}=await import(pathToFileURL(homedir()+'/.codex/playwright-runtime/runtime.mjs'));
import {writeFile,mkdir} from 'node:fs/promises';
const out=fileURLToPath(new URL('../../macos/Sources/Resources/Idle',import.meta.url));await mkdir(out,{recursive:true});
const b=await launchPinnedChromium();const p=await b.newPage();await p.goto(new URL('./index.html',import.meta.url).href);
await p.evaluate(()=>window.capture=true);
for(const id of (process.argv.slice(2).length?process.argv.slice(2):['blink','scan','tilt','nod','stretch','hop','balance','sneeze','sleep','dance','satellite-out','satellite-in'])){
 const data=await p.evaluate(id=>{
 const fps=30,duration=id==='dance'?20.783:id==='satellite-out'?.8:id==='satellite-in'?.82:7,frames=[],proj=new OpenBotMotion.SvgProjector({viewportSize:280});
 const path=document.createElementNS('http://www.w3.org/2000/svg','path');
 for(let i=0;i<Math.ceil(duration*fps);i++){
 const pose=poseFor(id,i/fps).bot,res=proj.projectRoundedCube(pose);path.setAttribute('d',res.bodyPath);const len=path.getTotalLength();
 // SVG hull start vertices change with rotation. Sample a fixed angular grid
 // around the bounds center, so index k always represents the same direction.
 const outline=Array.from({length:768},(_,k)=>path.getPointAtLength(k*len/768));
 const cx=(Math.min(...outline.map(p=>p.x))+Math.max(...outline.map(p=>p.x)))/2;
 const cy=(Math.min(...outline.map(p=>p.y))+Math.max(...outline.map(p=>p.y)))/2;
 const points=Array.from({length:192},(_,k)=>{
   const angle=2*Math.PI*k/192,dx=Math.cos(angle),dy=Math.sin(angle);
   let radius=Infinity;
   for(let j=0;j<outline.length;j++) {
     const a=outline[j],b=outline[(j+1)%outline.length];
     const ex=b.x-a.x,ey=b.y-a.y,den=dx*ey-dy*ex;
     if(Math.abs(den)<1e-10) continue;
     const ax=a.x-cx,ay=a.y-cy;
     const r=(ax*ey-ay*ex)/den,u=(ax*dy-ay*dx)/den;
     if(r>=0 && u>=-1e-8 && u<=1+1e-8) radius=Math.min(radius,r);
   }
   if(!Number.isFinite(radius)) throw new Error('Missing contour intersection');
   return [Math.round((cx+dx*radius)*1000)/1000,Math.round((cy+dy*radius)*1000)/1000];
 });
 const eyes=res.eyes.map(e=>({x:e.cx,y:e.cy,w:e.w,h:e.h,r:e.rx,angle:e.angle,opacity:e.opacity??1}));
 frames.push({points,eyes,body:pose.bodyColor,eye:pose.eyeColor});
 }
 return {fps,duration,frames};
 },id);await writeFile(`${out}/${id}.json`,JSON.stringify(data));console.log(id,data.frames.length);
}
await b.close();
