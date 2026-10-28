// Original SVG artwork rendered as PNGs for the public Supabase sample bucket.
// Rendering dependency stays in ignored build/; it is not an APK dependency.
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
const root=new URL('../',import.meta.url);
const require=createRequire(new URL('build/sample-media-tools/package.json',root));
const {Resvg}=require('@resvg/resvg-js');
const out=new URL('assets/sample-media/',root);mkdirSync(out,{recursive:true});
const navy='#24344c',blue='#2457d6',light='#a9bedf',gold='#b99c59';
const rect=(x,y,w,h,color,r=8)=>`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${color}"/>`;
const circle=(x,y,r,color)=>`<circle cx="${x}" cy="${y}" r="${r}" fill="${color}"/>`;
const text=(x,y,value,size=24,color=navy)=>`<text x="${x}" y="${y}" text-anchor="middle" font-family="Arial" font-weight="700" font-size="${size}" fill="${color}">${value}</text>`;
const fan=(x,y,r)=>circle(x,y,r,'#111e31')+Array.from({length:7},(_,i)=>`<ellipse cx="${x+r*.32}" cy="${y}" rx="${r*.52}" ry="${r*.17}" fill="#627da0" transform="rotate(${i*360/7} ${x} ${y})"/>`).join('')+circle(x,y,r*.22,light);
const cpu=rect(-95,-95,190,190,'#2c4d57')+
  Array.from({length:8},(_,i)=>rect(-80+i*22,-108,10,18,gold,1)+rect(-80+i*22,90,10,18,gold,1)+rect(-108,-80+i*22,18,10,gold,1)+rect(90,-80+i*22,18,10,gold,1)).join('')+
  rect(-72,-72,144,144,'#b4c1d4')+rect(-57,-57,114,114,'#e5ebf3')+text(0,12,'CPU',30);
const motherboard=rect(-150,-115,300,230,'#25454f')+rect(-133,-98,64,30,'#a4b4c6')+rect(-55,-55,110,110,'#b6c3d3')+rect(-40,-40,80,80,'#e4eaf2')+
  [83,105,127].map(x=>rect(x,-95,12,140,'#77949e',2)).join('')+
  [-110,-77].map(y=>rect(-130,y+180,230,14,'#96adba',2)).join('')+
  Array.from({length:5},(_,i)=>rect(-134+i*25,-20,17,28,'#172b38',2)).join('')+circle(115,86,17,'#bec7d2');
const gpu=rect(-190,-75,380,145,navy,15)+rect(-181,-66,360,13,'#58708e',5)+fan(-85,0,58)+fan(80,0,58)+rect(-120,74,180,14,gold,1)+rect(-205,-85,15,160,'#8d9eb4',2);
const ram=[-53,37].map(y=>rect(-190,y,380,65,navy,5)+Array.from({length:8},(_,i)=>rect(-173+i*43,y+12,32,32,'#566d88',3)).join('')+rect(-165,y+65,330,10,gold,1)).join('');
const storage=rect(-195,-48,390,96,'#263c48',8)+rect(-166,-31,95,62,'#111e2a',3)+rect(-56,-31,183,62,'#dfe7f1',3)+text(34,8,'NVMe SSD',22)+rect(169,-33,25,66,gold,1)+circle(-184,0,7,'#aab9c5');
const psu=rect(-145,-107,290,214,navy,12)+fan(-25,0,83)+Array.from({length:9},(_,i)=>rect(90,-82+i*20,31,7,'#687e98',2)).join('')+`<path d="M145 34 C220 30 164 145 230 133 M145 54 C202 61 180 158 245 154" fill="none" stroke="#3f5572" stroke-width="12"/>`;
const casePart=rect(-100,-157,200,314,navy,13)+rect(-83,-137,130,263,'#426689',5)+rect(57,-137,26,263,'#16263a',4)+[ -88,-3,82 ].map(y=>circle(70,y,9,light)).join('')+rect(-86,157,40,12,navy,2)+rect(46,157,40,12,navy,2)+`<path d="M-67 -120 L25 -120 L-67 60 Z" fill="#7393b6" opacity=".4"/>`;
const cooler=rect(-118,-117,236,218,'#a4b2c6',8)+Array.from({length:14},(_,i)=>rect(-131,-110+i*15,262,5,'#d8e0e9',1)).join('')+`<path d="M-58 99 L-58 145 L-18 145 L-18 99 M18 99 L18 145 L58 145 L58 99" fill="none" stroke="${gold}" stroke-width="13"/>`+rect(-105,-105,210,210,navy,10)+fan(0,0,88);
const monitor=rect(-180,-120,360,230,navy,12)+rect(-165,-105,330,197,'#5279b8',4)+`<path d="M-165 -105 L100 -105 L-165 92 Z" fill="#9bb4df" opacity=".45"/>`+rect(-17,110,34,54,'#607895',3)+rect(-85,161,170,14,navy,4);
const peripherals=rect(-225,-90,450,180,navy,14)+Array.from({length:5},(_,row)=>Array.from({length:14},(_,col)=>rect(-206+col*29,-70+row*28,23,21,(row+col)%5===0?'#829fc8':'#c7d2e1',3)).join('')).join('')+rect(-97,43,174,21,'#e5eaf2',3);
const hardware={cpu,motherboard,gpu,ram,storage,psu,casePart,cooler,monitor,peripherals};
const labels={cpu:'Processor',motherboard:'Motherboard',gpu:'Graphics card',ram:'Memory',storage:'Solid-state drive',psu:'Power supply',casePart:'PC case',cooler:'CPU cooler',monitor:'Monitor',peripherals:'Keyboard &amp; peripherals'};
function page(content,label){return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="768" viewBox="0 0 800 600"><defs><linearGradient id="bg" x2="1" y2="1"><stop stop-color="#eaf0ff"/><stop offset="1" stop-color="#f3f5fa"/></linearGradient></defs><rect width="800" height="600" fill="url(#bg)"/><ellipse cx="400" cy="427" rx="210" ry="24" fill="#d7e1f0" opacity=".6"/><g transform="translate(400 275) rotate(-7)">${content}</g>${text(400,508,label,27)}${text(400,547,'COMPARTS · Sample illustration',16,'#61738c')}</svg>`;}
function avatar(seller){return `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><rect width="256" height="256" rx="128" fill="${seller?'#e6edff':'#e4f3ee'}"/>${circle(128,86,37,seller?blue:'#247150')}<path d="M53 205 C53 128 203 128 203 205Z" fill="${seller?blue:'#247150'}"/>${circle(195,195,46,'white')}${seller?rect(165,186,60,37,navy,4)+rect(160,170,70,20,blue,4)+rect(187,198,15,25,'#e5ecf7',2):rect(171,178,49,47,'#247150',5)+`<path d="M183 180 V171 A13 13 0 0 1 209 171 V180" fill="none" stroke="#247150" stroke-width="7"/>`}</svg>`;}
const logo=`<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><rect width="256" height="256" rx="40" fill="${blue}"/><g transform="translate(128 108) scale(.55)">${cpu}</g>${text(128,216,'COMPARTS',28,'white')}</svg>`;
const entries=[...Object.entries(hardware).map(([category,art])=>({path:`categories/${category}.png`,category,label:labels[category].replace('&amp;','&'),svg:page(art,labels[category])})),
  {path:'avatars/seller.png',role:'seller',label:'Sample seller avatar',svg:avatar(true)},
  {path:'avatars/buyer.png',role:'buyer',label:'Sample buyer avatar',svg:avatar(false)},
  {path:'branding/shop-logo.png',label:'COMPARTS sample shop logo',svg:logo}];
const fonts=['C:/Windows/Fonts/arial.ttf','C:/Windows/Fonts/arialbd.ttf'].filter(existsSync);
const manifest=[];
for(const {svg,...entry} of entries){
  const file=new URL(entry.path,out);mkdirSync(new URL('./',file),{recursive:true});
  writeFileSync(new URL(entry.path.replace('.png','.svg'),out),svg+'\n');
  const png=new Resvg(svg,{font:{loadSystemFonts:fonts.length===0,fontFiles:fonts}}).render().asPng();
  writeFileSync(file,png);manifest.push({...entry,sha256:createHash('sha256').update(png).digest('hex'),bytes:png.length});
}
writeFileSync(new URL('manifest.json',out),JSON.stringify(manifest,null,2)+'\n');
const sheet=`<svg xmlns="http://www.w3.org/2000/svg" width="1020" height="1275"><rect width="1020" height="1275" fill="white"/>${manifest.map((entry,index)=>{
  const x=index%3*340,y=Math.floor(index/3)*255;
  return `<image x="${x+8}" y="${y+8}" width="324" height="218" preserveAspectRatio="xMidYMid meet" href="data:image/png;base64,${readFileSync(new URL(entry.path,out)).toString('base64')}"/>`+text(x+170,y+246,entry.path,13);
}).join('')}</svg>`;
writeFileSync(new URL('build/sample-media-contact-sheet.png',root),new Resvg(sheet,{font:{loadSystemFonts:fonts.length===0,fontFiles:fonts}}).render().asPng());
console.log(JSON.stringify({rendered:manifest.length,output:'assets/sample-media',bytes:manifest.reduce((sum,item)=>sum+item.bytes,0)},null,2));
