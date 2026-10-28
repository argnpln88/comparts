// Android-device UI test helper. Operates only inside the COMPARTS app.
import {execFileSync} from 'node:child_process';
import {mkdirSync} from 'node:fs';
import assert from 'node:assert/strict';
const adb='F:/RigMarketAndroidSdk/platform-tools/adb.exe';
const run=(...args)=>execFileSync(adb,['-s','emulator-5554',...args],{encoding:'utf8',timeout:20000});
const decode=value=>value.replace(/&#(\d+);/g,(_,n)=>String.fromCharCode(+n)).replace(/&quot;/g,'"').replace(/&apos;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&');
function snapshot(){
  run('shell','uiautomator','dump','/sdcard/comparts-e2e-ui.xml');
  const xml=run('shell','cat','/sdcard/comparts-e2e-ui.xml');
  assert.ok(xml.includes('package="com.rigmarket.rigmarket"'),'COMPARTS is not the active app; no input sent');
  return [...xml.matchAll(/<node\s+([^>]+)>?/g)].map(match=>Object.fromEntries([...match[1].matchAll(/([\w-]+)="([^"]*)"/g)].map(([,k,v])=>[k,decode(v)])))
    .filter(node=>node.package==='com.rigmarket.rigmarket').map(node=>{
      const b=(node.bounds??'').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
      return {...node,box:b?b.slice(1).map(Number):null};
    });
}
function choose(nodes,pattern,fields=false){
  const regex=new RegExp(pattern);
  const matches=nodes.filter(n=>n.box&&n.box[2]>n.box[0]&&n.box[3]>n.box[1]&&n.enabled==='true'&&
    (!fields||n.class==='android.widget.EditText')&&regex.test([n['content-desc'],n.text,n.hint].filter(Boolean).join('\n')));
  return matches.find(n=>n.clickable==='true')??matches[0];
}
function tap(node){assert.ok(node?.box,'UI target not found; no input sent');const [x1,y1,x2,y2]=node.box;
  const targetX=process.argv.includes('--leading')?x1+Math.min(x2-x1,y2-y1)/2:(x1+x2)/2;
  run('shell','input','tap',String(Math.round(targetX)),String(Math.round((y1+y2)/2)));}
const [action,selector,value]=process.argv.slice(2);
if(action==='launch'){
  run('shell','am','start','-W','-n','com.rigmarket.rigmarket/.MainActivity');
  console.log('Launched COMPARTS');
}else if(action==='screenshot'){
  assert.match(selector,/^[a-z0-9-]+$/);mkdirSync('build/ui-e2e',{recursive:true});
  run('shell','screencap','-p',`/sdcard/${selector}.png`);run('pull',`/sdcard/${selector}.png`,`build/ui-e2e/${selector}.png`);
  console.log(JSON.stringify({screenshot:`build/ui-e2e/${selector}.png`}));
}else{
  let nodes=snapshot();
  if(action==='tap'||action==='fill'){
    let node=choose(nodes,selector,action==='fill');
    if(!node&&process.argv.includes('--scroll')){
      for(let i=0;i<5&&!node;i++){run('shell','input','swipe','1000','2400','1000','850','350');nodes=snapshot();node=choose(nodes,selector,action==='fill');}
    }
    assert.ok(node,`UI target not found: ${selector}`);tap(node);
    if(action==='fill'){
      assert.match(value,/^[A-Za-z0-9 @.,_+\-]+$/,'Unsupported test input; no text sent');
      run('shell','input','keyevent','123');run('shell','input','keyevent',...Array(Math.max(64,(node.text??'').length)).fill('67'));
      run('shell','input','text',value.replaceAll(' ','%s'));
    }
    console.log(JSON.stringify({action,target:selector}));
  }else if(action==='fill-index'){
    const node=nodes.filter(n=>n.class==='android.widget.EditText')[Number(selector)];
    assert.ok(node,'Editable field not found');assert.match(value,/^[A-Za-z0-9 @.,_+\-]+$/);
    tap(node);run('shell','input','keyevent','123');run('shell','input','keyevent',...Array(Math.max(64,(node.text??'').length)).fill('67'));run('shell','input','text',value.replaceAll(' ','%s'));
    console.log(JSON.stringify({action,field:Number(selector)}));
  }else if(action==='scroll-down'){
    run('shell','input','swipe','1000','2400','1000','850','350');
    console.log('Scrolled down');
  }else if(action==='scroll-top'){
    run('shell','input','swipe','1000','700','1000','2450','350');run('shell','input','swipe','1000','700','1000','2450','350');
    console.log('Scrolled to top');
  }else if(action!=='state'){throw new Error('Unknown UI test action');}
  nodes=snapshot();
  const inputs=nodes.filter(n=>n.class==='android.widget.EditText');
  console.log(JSON.stringify(nodes.filter(n=>n['content-desc']||n.text||n.class==='android.widget.EditText').map(n=>({
    label:(n['content-desc']||n.hint||'').slice(0,260),
    ...(n.class==='android.widget.EditText'?{field:inputs.indexOf(n),value:n.password==='true'?'[hidden]':n.text||''}:n.text?{text:n.text.slice(0,160)}:{}),
    ...(n.clickable==='true'?{button:true}:{}),
    ...(process.argv.includes('--bounds')?{bounds:n.box}:{}),
  }))));
}
