// Read-only backend assertions for the order created through Android UI.
import './connection-env.mjs';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url),file=new URL('build/ui-e2e/result.json',root);
const fixture=JSON.parse(readFileSync(new URL('.env.commerce-demo.json',root),'utf8'));
const ref=readFileSync(new URL('supabase/.temp/project-ref',root),'utf8').trim();assert.match(ref,/^[a-z0-9]+$/);
const keys=JSON.parse(execFileSync('cmd.exe',['/d','/c',`npx.cmd --yes supabase projects api-keys --project-ref ${ref} --reveal --output json`],{cwd:root,encoding:'utf8'}));
const service=keys.find(k=>k.name==='service_role').api_key;
const key=keys.find(k=>k.type==='secret'&&k.name==='default')?.api_key??service;
async function get(path){const r=await fetch(`https://${ref}.supabase.co/rest/v1/${path}`,{headers:{apikey:key,Authorization:`Bearer ${service}`},signal:AbortSignal.timeout(20000)});assert.ok(r.ok,`Read failed: ${r.status}`);return r.json();}
const stage=process.argv[2];
let record;
if(stage==='init'){
  const orders=await get(`orders?buyer_id=eq.${fixture.buyer.id}&select=product_id,status`);
  const products=await get(`products?id=in.(${fixture.products.map(p=>p.id).join(',')})&select=id,name,stock,price_centavos,status`);
  const candidates=[4,5,1,2,0,3].map(i=>products.find(p=>p.id===fixture.products[i].id));
  const product=candidates.find(p=>p&&p.status==='published'&&p.stock>0&&!orders.some(o=>o.product_id===p.id&&['cod_pending','creating','creation_unknown','payment_pending','payment_review'].includes(o.status)));
  assert.ok(product,'No independent in-stock sample product available');
  record={started_at:new Date().toISOString(),product,buyer_id:fixture.buyer.id,seller_id:fixture.seller.id,
    tracking_number:`CP-UI-${randomUUID().slice(0,8).toUpperCase()}`,
    shipping:{recipient:'UI Test Buyer',phone:'09171234567',address:'123 UI Test Street Barangay Demo',city:'Quezon City Metro Manila',postal_code:'1100'},
    review_notes:'UI test purchase arrived in good condition. Demo delivery and cash payment confirmed.',checks:[]};
}else{
  record=JSON.parse(readFileSync(file,'utf8'));
  let order;
  if(stage==='placed'){
    const rows=await get(`orders?buyer_id=eq.${record.buyer_id}&product_id=eq.${record.product.id}&created_at=gte.${encodeURIComponent(record.started_at)}&select=*`);
    assert.equal(rows.length,1,'UI must create exactly one new order');order=rows[0];record.order_id=order.id;
  }else{
    order=(await get(`orders?id=eq.${record.order_id}&select=*`))[0];assert.ok(order);
  }
  assert.equal(order.buyer_id,record.buyer_id);assert.equal(order.seller_id,record.seller_id);
  assert.equal(order.payment_method,'cod');assert.equal(order.fulfillment,'delivery');assert.equal(order.quantity,1);
  assert.equal(order.total_centavos,record.product.price_centavos);assert.deepEqual(order.shipping_address,record.shipping);
  assert.ok(!order.payment_session_id&&!order.payment_request_id,'COD must not create an online charge');
  const stock=(await get(`products?id=eq.${record.product.id}&select=stock`))[0].stock;
  assert.equal(stock,record.product.stock-1,'One unit must be reserved exactly once');
  const expected={placed:['cod_pending','processing'],shipped:['cod_pending','shipped'],received:['paid','delivered'],reviewed:['paid','delivered']}[stage];
  assert.ok(expected);assert.equal(order.status,expected[0]);assert.equal(order.fulfillment_status,expected[1]);
  if(stage!=='placed') {assert.equal(order.courier,'COMPARTS Demo Courier');assert.equal(order.tracking_number,record.tracking_number);assert.ok(order.shipped_at);}
  if(['received','reviewed'].includes(stage)) {assert.ok(order.delivered_at);assert.ok(order.paid_at);}
  if(stage==='reviewed'){
    const reviews=await get(`order_reviews?order_id=eq.${record.order_id}&select=rating,review_notes,buyer_id`);
    assert.equal(reviews.length,1);assert.equal(reviews[0].rating,5);assert.equal(reviews[0].review_notes,record.review_notes);assert.equal(reviews[0].buyer_id,record.buyer_id);
    const events=await get(`order_delivery_events?order_id=eq.${record.order_id}&select=event,actor_id&order=created_at`);
    assert.deepEqual(events.map(e=>e.event),['placed','shipped','received']);
    assert.deepEqual(events.map(e=>e.actor_id),[record.buyer_id,record.seller_id,record.buyer_id]);
    record.review=reviews[0];record.events=events;record.finished_at=new Date().toISOString();
  }
  record.checks.push({stage,status:order.status,fulfillment_status:order.fulfillment_status,stock,checked_at:new Date().toISOString()});
}
mkdirSync(new URL('build/ui-e2e/',root),{recursive:true});writeFileSync(file,JSON.stringify(record,null,2)+'\n');
console.log(JSON.stringify({stage,product:record.product.name,price_centavos:record.product.price_centavos,tracking_number:record.tracking_number,order_id:record.order_id,checks:record.checks},null,2));
