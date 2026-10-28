// Upload and verify sample media; project keys and Auth tokens stay in memory.
import './connection-env.mjs';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url);
const ref=readFileSync(new URL('supabase/.temp/project-ref',root),'utf8').trim();
assert.match(ref,/^[a-z0-9]+$/);
const keys=JSON.parse(execFileSync('cmd.exe',['/d','/c',`npx.cmd --yes supabase projects api-keys --project-ref ${ref} --reveal --output json`],{cwd:root,encoding:'utf8'}));
const service=keys.find(k=>k.name==='service_role')?.api_key;
const secret=keys.find(k=>k.type==='secret'&&k.name==='default')?.api_key??service;
const publicKey=keys.find(k=>k.type==='publishable')?.api_key??keys.find(k=>k.name==='anon')?.api_key;
assert.ok(service&&publicKey);
const base=`https://${ref}.supabase.co`,bucket='comparts-sample-media';
const manifest=JSON.parse(readFileSync(new URL('assets/sample-media/manifest.json',root),'utf8'));
const assets=manifest.map(entry=>({...entry,object:entry.path.replace(/\.png$/,`-${entry.sha256.slice(0,12)}.png`)}));
const url=entry=>`${base}/storage/v1/object/public/${bucket}/${entry.object}`;
const accountGroups=['.env.commerce-demo.json','.env.payment-test.json'].map(file=>JSON.parse(readFileSync(new URL(file,root),'utf8')));
const accounts=accountGroups.flatMap(group=>['seller','buyer','outsider'].filter(role=>group[role]?.id).map(role=>({...group[role],role})));
const sellerIds=accounts.filter(account=>account.role==='seller').map(account=>account.id);
const ownedProducts=`/rest/v1/products?seller_id=in.(${sellerIds.join(',')})&select=id,seller_id,name,category_id,image_url,image_is_illustration&order=name`;
async function request(path,{token=service,method='GET',body,raw=false,headers={}}={}){
  const response=await fetch(base+path,{method,headers:{apikey:token===service?secret:publicKey,...(token===publicKey?{}:{Authorization:`Bearer ${token}`}),
    'Content-Type':raw?'image/png':'application/json',...headers},body:body===undefined?undefined:raw?body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
  const data=await response.json().catch(()=>null);
  assert.ok(response.ok,`${method} ${path}: HTTP ${response.status}: ${JSON.stringify(data)}`);
  return data;
}
const action=process.argv[2]??'verify';
const users=[];
for(const account of accounts){
  const user=await request(`/auth/v1/admin/users/${account.id}`);
  assert.equal(user.email,account.email);assert.equal(user.app_metadata?.rigmarket_test,true);
  assert.ok(user.email_confirmed_at);users.push({account,user});
}
const products=await request(ownedProducts);
if(action==='audit'){
  console.log(JSON.stringify({sample_auth_accounts:users.length,sample_sellers:sellerIds.length,hosted_sample_products:products.length,
    products_with_images:products.filter(p=>!!p.image_url).length,accounts_with_avatars:users.filter(({user})=>!!user.user_metadata?.avatar_url).length},null,2));
}else{
  const storedBucket=await request(`/storage/v1/bucket/${bucket}`);
  assert.equal(storedBucket.public,true,'Expected a public sample media bucket');
  if(action==='upload'){
    for(const entry of assets){
      const png=readFileSync(new URL(`assets/sample-media/${entry.path}`,root));
      assert.equal(createHash('sha256').update(png).digest('hex'),entry.sha256);
      await request(`/storage/v1/object/${bucket}/${entry.object}`,{method:'POST',raw:true,body:png,headers:{'x-upsert':'true','cache-control':'max-age=31536000'}});
    }
    for(const product of products){
      assert.ok(!product.image_url||product.image_url.startsWith(`${base}/storage/v1/object/public/${bucket}/`),'Existing non-sample photo preserved; review it before changing');
      const art=assets.find(entry=>entry.category===product.category_id);assert.ok(art,`Missing category art for ${product.category_id}`);
      const result=await request(`/rest/v1/products?id=eq.${product.id}&seller_id=eq.${product.seller_id}`,{method:'PATCH',headers:{Prefer:'return=representation'},body:{image_url:url(art),image_is_illustration:true}});
      assert.equal(result.length,1);
    }
    const logo=url(assets.find(entry=>entry.path==='branding/shop-logo.png'));
    for(const {account,user} of users){
      const avatar=url(assets.find(entry=>entry.role===(account.role==='seller'?'seller':'buyer')));
      await request(`/auth/v1/admin/users/${account.id}`,{method:'PUT',body:{user_metadata:{...user.user_metadata,avatar_url:avatar}}});
      const profiles=await request(`/rest/v1/profiles?id=eq.${account.id}`,{method:'PATCH',headers:{Prefer:'return=representation'},body:{avatar_url:avatar}});
      assert.equal(profiles.length,1,'Missing sample database profile');
      if(account.role==='seller'){
        const shops=await request(`/rest/v1/seller_profiles?id=eq.${account.id}`,{method:'PATCH',headers:{Prefer:'return=representation'},body:{logo_url:logo}});
        assert.equal(shops.length,1,'Missing sample shop profile');
      }
    }
  }
  let images=0,signins=0;let buyerToken;
  for(const entry of assets){
    const response=await fetch(url(entry),{signal:AbortSignal.timeout(20000)});assert.equal(response.status,200);
    assert.ok(response.headers.get('content-type')?.startsWith('image/png'));
    const png=Buffer.from(await response.arrayBuffer());assert.equal(png.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
    assert.equal(createHash('sha256').update(png).digest('hex'),entry.sha256,'Public object differs from uploaded media');images++;
  }
  const hosted=await request(ownedProducts,{token:publicKey});
  assert.equal(hosted.length,products.length);
  for(const product of hosted){
    assert.equal(product.image_url,url(assets.find(entry=>entry.category===product.category_id)));
    assert.equal(product.image_is_illustration,true);
  }
  for(const {account} of users){
    const login=await request('/auth/v1/token?grant_type=password',{token:publicKey,method:'POST',body:{email:account.email,password:account.password}});
    assert.equal(login.user.id,account.id);assert.ok(login.user.user_metadata.avatar_url.startsWith(`${base}/storage/v1/object/public/${bucket}/`));
    const profile=await request(`/rest/v1/profiles?id=eq.${account.id}&select=id,avatar_url`,{token:login.access_token});
    assert.equal(profile.length,1);assert.equal(profile[0].avatar_url,login.user.user_metadata.avatar_url);
    if(account.role==='buyer')buyerToken=login.access_token;signins++;
  }
  const shops=await request(`/rest/v1/seller_profiles?id=in.(${sellerIds.join(',')})&select=id,logo_url`,{token:publicKey});
  assert.equal(shops.length,sellerIds.length);assert.ok(shops.every(s=>s.logo_url===url(assets.find(entry=>entry.path==='branding/shop-logo.png'))));
  const samplePng=readFileSync(new URL(`assets/sample-media/${assets[0].path}`,root));
  for(const token of [null,buyerToken]){
    const response=await fetch(`${base}/storage/v1/object/${bucket}/checks/${randomUUID()}.png`,{method:'POST',headers:{apikey:publicKey,...(token?{Authorization:`Bearer ${token}`}:{}) ,'Content-Type':'image/png'},body:samplePng,signal:AbortSignal.timeout(20000)});
    const error=await response.json();
    assert.ok(!response.ok&&[401,403].includes(Number(error.statusCode??response.status)),'Public/client media upload was not denied');
  }
  console.log(JSON.stringify({bucket,public_images_verified:images,hosted_sample_products_with_images:hosted.length,
    sample_auth_accounts_and_database_profiles:signins,shop_logos_verified:shops.length,anonymous_and_buyer_uploads_blocked:true},null,2));
}
