// Add development fixtures without replacing existing listings or purchases.
import './connection-env.mjs';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url);
const ref=readFileSync(new URL('supabase/.temp/project-ref',root),'utf8').trim();
assert.match(ref,/^[a-z0-9]+$/);
const keys=JSON.parse(execFileSync('cmd.exe',['/d','/c',`npx.cmd --yes supabase projects api-keys --project-ref ${ref} --reveal --output json`],{cwd:root,encoding:'utf8'}));
const service=keys.find(k=>k.name==='service_role')?.api_key;
const secret=keys.find(k=>k.type==='secret'&&k.name==='default')?.api_key??service;
const publicKey=keys.find(k=>k.type==='publishable')?.api_key??keys.find(k=>k.name==='anon')?.api_key;
assert.ok(service&&publicKey);
const base=`https://${ref}.supabase.co`;
const file=new URL('.env.commerce-demo.json',root),fixture=JSON.parse(readFileSync(file,'utf8'));
const legacy=JSON.parse(readFileSync(new URL('.env.payment-test.json',root),'utf8'));
const manifest=JSON.parse(readFileSync(new URL('assets/sample-media/manifest.json',root),'utf8'));
async function request(path,{token=service,method='GET',body,raw=false,expected=[200,201,204],headers={}}={}){
  const response=await fetch(base+path,{method,headers:{apikey:token===service?secret:publicKey,
    ...(token===publicKey?{}:{Authorization:`Bearer ${token}`}),
    'Content-Type':raw?'image/png':'application/json',...headers},
    body:body===undefined?undefined:raw?body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
  const data=await response.json().catch(()=>null);
  assert.ok(expected.includes(response.status),`${method} ${path}: ${response.status}: ${JSON.stringify(data)}`);
  return data;
}
const login=async account=>(await request('/auth/v1/token?grant_type=password',{token:publicKey,method:'POST',body:{email:account.email,password:account.password}})).access_token;
const buyer=await login(fixture.buyer),seller=await login(fixture.seller),outsider=await login(legacy.outsider);
const user=await request(`/auth/v1/admin/users/${fixture.seller.id}`);
assert.equal(user.app_metadata.comparts_demo,true);
const shipping={recipient:'Sample Buyer',phone:'09171234567',address:'123 Sample Street, Barangay Demo',city:'Quezon City, Metro Manila',postal_code:'1100'};
const report={};
if(process.argv[2]!=='verify'){
  // At least three distinct sample variants per category, including existing fixtures.
  const variants={
    cpu:[['AMD Ryzen 5 7600','AMD',1099500,{Socket:'AM5',Cores:'6 cores / 12 threads'}],['Intel Core i5-12400F','Intel',649500,{Socket:'LGA1700',Cores:'6 cores / 12 threads'}]],
    motherboard:[['Gigabyte B650M Gaming WiFi','Gigabyte',929500,{Socket:'AM5',Memory:'DDR5'}],['ASRock B760M DDR4','ASRock',699500,{Socket:'LGA1700',Memory:'DDR4'}]],
    gpu:[['MSI GeForce RTX 4060 8 GB','MSI',1895000,{VRAM:'8 GB GDDR6',Interface:'PCIe 4.0'}],['Sapphire Radeon RX 6600 8 GB','Sapphire',999500,{VRAM:'8 GB GDDR6',Interface:'PCIe 4.0'}]],
    ram:[['Corsair Vengeance DDR5 32 GB','Corsair',629500,{Capacity:'32 GB (2 x 16 GB)',Speed:'6000 MT/s'}],['Kingston Fury Beast DDR4 16 GB','Kingston',249500,{Capacity:'16 GB (2 x 8 GB)',Speed:'3200 MT/s'}]],
    storage:[['WD Black SN770 1 TB NVMe SSD','Western Digital',459500,{Capacity:'1 TB',Interface:'PCIe 4.0 NVMe'}],['Seagate Barracuda 2 TB HDD','Seagate',329500,{Capacity:'2 TB',Interface:'SATA'}]],
    psu:[['Corsair RM650 650 W Power Supply','Corsair',499500,{Wattage:'650 W',Efficiency:'80 Plus Gold'}],['Cooler Master MWE Bronze 650 W','Cooler Master',349500,{Wattage:'650 W',Efficiency:'80 Plus Bronze'}]],
    casePart:[['Corsair 4000D Airflow Mid Tower','Corsair',499500,{Motherboard:'ATX / Micro-ATX',Panel:'Tempered glass'}],['Montech Air 100 Mesh Case','Montech',269500,{Motherboard:'Micro-ATX / Mini-ITX',Panel:'Mesh front'}]],
    cooler:[['DeepCool AK400 CPU Cooler','DeepCool',159500,{Fan:'120 mm',Compatibility:'AM4 / AM5 / LGA1700'}],['Arctic P12 PWM 120 mm Fan','Arctic',49500,{Size:'120 mm',Control:'4-pin PWM'}]],
    monitor:[['AOC 24-inch Gaming Monitor','AOC',899500,{Resolution:'1920 x 1080',Refresh:'180 Hz'}],['LG 27-inch QHD Monitor','LG',1199500,{Resolution:'2560 x 1440',Panel:'IPS'}]],
    peripherals:[['Keychron C3 Mechanical Keyboard','Keychron',249500,{Layout:'Tenkeyless',Connection:'USB wired'}],['Logitech Wireless Gaming Mouse','Logitech',199500,{Connection:'2.4 GHz wireless',Sensor:'Optical'}]],
  };
  const thirds={
    cpu:['AMD Ryzen 7 7700','AMD',1699500],
    motherboard:['MSI B550M PRO-VDH WiFi','MSI',649500],
    gpu:['ASUS GeForce RTX 3060 12 GB','ASUS',1599500],
    ram:['G.Skill Ripjaws V DDR4 32 GB','G.Skill',429500],
    storage:['Samsung 990 EVO 1 TB NVMe SSD','Samsung',549500],
    psu:['Seasonic Focus GX-750 Power Supply','Seasonic',699500],
    casePart:['NZXT H5 Flow Mid Tower','NZXT',549500],
    cooler:['Thermalright Peerless Assassin 120 SE','Thermalright',249500],
    monitor:['ASUS TUF 24-inch Gaming Monitor','ASUS',999500],
    peripherals:['HyperX Cloud Stinger 2 Headset','HyperX',249500],
  };
  for(const [category,part] of Object.entries(thirds))variants[category].push([...part,{Purpose:'Illustrative COMPARTS sample listing'}]);
  const existing=await request(`/rest/v1/products?seller_id=eq.${fixture.seller.id}&status=eq.published&select=id,name,category_id`);
  let added=0;
  for(const [category,parts] of Object.entries(variants)){
    for(const [name,brand,price,specifications] of parts){
      if(existing.some(p=>p.category_id===category&&p.name===name)) continue;
      const art=manifest.find(a=>a.category===category);assert.ok(art);
      const object=art.path.replace(/\.png$/,`-${art.sha256.slice(0,12)}.png`);
      const id=randomUUID();
      await request('/rest/v1/products',{method:'POST',body:{id,seller_id:fixture.seller.id,category_id:category,name,brand,
        price_centavos:price,stock:20,condition:'new',status:'published',specifications,
        image_url:`${base}/storage/v1/object/public/comparts-sample-media/${object}`,image_is_illustration:true,
        description:`${name}. Sample catalog item for demonstrating COMPARTS shopping and delivery.`,
        warranty:'Sample listing. Confirm warranty and return terms with the seller before a real purchase.'}});
      existing.push({id,name,category_id:category});added++;
    }
  }
  const saved=await request(`/rest/v1/delivery_addresses?buyer_id=eq.${fixture.buyer.id}`);
  if(!saved.length) await request('/rest/v1/rpc/save_delivery_address',{token:buyer,method:'POST',body:{p_shipping:shipping}});
  report.sample_items_added=added;

  // Leave one explicitly labeled sample review with an illustration, never a fake customer photograph.
  const reviews=await request(`/rest/v1/order_reviews?buyer_id=eq.${fixture.buyer.id}&select=order_id,photo_paths`);
  if(!reviews.some(r=>r.photo_paths.length)){
    const product=fixture.products[2];
    const call=(token,body)=>request('/functions/v1/commerce-order',{token,method:'POST',body});
    const placed=(await call(buyer,{action:'create_cod',product_id:product.id,quantity:1,
      expected_unit_price_centavos:product.price,idempotency_key:randomUUID(),shipping_address:shipping})).order;
    await call(seller,{action:'dispatch',order_id:placed.id,courier:'Sample Courier',tracking_number:`SAMPLE-${placed.id.slice(0,8)}`});
    await call(buyer,{action:'receive',order_id:placed.id});
    const art=manifest.find(a=>a.category==='storage');
    const png=readFileSync(new URL(`assets/sample-media/${art.path}`,root));
    const path=`${placed.id}/${randomUUID()}.png`;
    await request(`/storage/v1/object/review-photos/${path}`,{token:buyer,method:'POST',raw:true,body:png});
    await call(buyer,{action:'review',order_id:placed.id,rating:5,
      review_notes:'Sample review: item received in good condition. Attached image is a sample item illustration, not a customer photograph.',photo_paths:[path]});
    fixture.photo_review_order_id=placed.id;
    writeFileSync(file,JSON.stringify(fixture,null,2)+'\n');
    report.sample_photo_review_added=true;
  }
}
const categories=await request('/rest/v1/categories?select=id,name',{token:publicKey});
const products=await request('/rest/v1/products?status=eq.published&select=id,category_id,image_url',{token:publicKey});
report.category_counts=Object.fromEntries(categories.map(c=>[c.name,products.filter(p=>p.category_id===c.id).length]));
assert.ok(Object.values(report.category_counts).every(n=>n>=3),'Each category needs at least three published sample items.');
const own=await request('/rest/v1/delivery_addresses?select=buyer_id,address',{token:buyer});
assert.equal(own.length,1);assert.equal(own[0].buyer_id,fixture.buyer.id);
const privateAddress=await request(`/rest/v1/delivery_addresses?buyer_id=eq.${fixture.buyer.id}`,{token:outsider});assert.equal(privateAddress.length,0);
await request('/rest/v1/delivery_addresses',{token:buyer,method:'POST',body:{buyer_id:legacy.outsider.id,address:shipping},expected:[401,403]});
await request('/rest/v1/rpc/save_delivery_address',{token:buyer,method:'POST',body:{p_shipping:{...shipping,postal_code:'bad'}},expected:[400]});
report.saved_address_and_privacy_verified=true;
const review=await request(`/rest/v1/order_reviews?buyer_id=eq.${fixture.buyer.id}&select=order_id,product_id,photo_paths`);
const photoReview=review.find(r=>r.photo_paths.length);assert.ok(photoReview);
const detail=await request('/functions/v1/commerce-order',{token:buyer,method:'POST',body:{action:'get',order_id:photoReview.order_id}});
assert.deepEqual(detail.review.photo_paths,photoReview.photo_paths);
await request('/rest/v1/rpc/commerce_review',{token:buyer,method:'POST',body:{p_actor:fixture.buyer.id,p_order:photoReview.order_id,p_rating:5,p_notes:'Unauthorized direct write',p_photos:[]},expected:[401,403,404]});
await request('/functions/v1/commerce-order',{token:buyer,method:'POST',body:{action:'review',order_id:photoReview.order_id,rating:5,review_notes:'Invalid foreign item photo',photo_paths:[`${randomUUID()}/${randomUUID()}.png`]},expected:[409]});
const summary=await request('/rest/v1/rpc/product_review_summary',{token:publicKey,method:'POST',body:{p_product:photoReview.product_id}});
assert.ok(summary.reviews.some(r=>r.photo_paths?.length));
assert.ok(summary.reviews.every(r=>!('buyer_id'in r)&&!('order_id'in r)));
const publicPhoto=await fetch(`${base}/storage/v1/object/public/review-photos/${photoReview.photo_paths[0]}`);
assert.equal(publicPhoto.status,200);
const png=readFileSync(new URL('assets/sample-media/categories/cpu.png',root));
for(const [token,id] of [[buyer,fixture.pending_order_id],[outsider,photoReview.order_id],[buyer,photoReview.order_id],[publicKey,photoReview.order_id]]){
  // Unreceived orders, unrelated buyers, submitted reviews and anonymous users cannot upload.
  const response=await fetch(`${base}/storage/v1/object/review-photos/${id}/${randomUUID()}.png`,{
    method:'POST',headers:{apikey:publicKey,...(token===publicKey?{}:{Authorization:`Bearer ${token}`}),'Content-Type':'image/png'},body:png});
  assert.equal(response.ok,false);const error=await response.json();assert.ok([401,403].includes(Number(error.statusCode??response.status)));
}
report.public_review_photo_and_upload_guards_verified=true;
console.log(JSON.stringify(report,null,2));
