// Provision only explicit demo accounts. Keys stay in memory; credentials are local and ignored.
import './connection-env.mjs';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
const root = new URL('../', import.meta.url);
const ref = readFileSync(new URL('supabase/.temp/project-ref', root), 'utf8').trim();
if (!/^[a-z0-9]+$/.test(ref)) throw new Error('Invalid project reference');
const keys = JSON.parse(execFileSync('cmd.exe', ['/d','/c',`npx.cmd --yes supabase projects api-keys --project-ref ${ref} --reveal --output json`], {cwd:root,encoding:'utf8'}));
const service = keys.find(k => k.name === 'service_role')?.api_key;
const backendKey = keys.find(k => k.type === 'secret' && k.name === 'default')?.api_key ?? service;
const publishable = keys.find(k => k.type === 'publishable')?.api_key ?? keys.find(k => k.name === 'anon')?.api_key;
if (!service || !publishable) throw new Error('Required project credentials unavailable');
const base = `https://${ref}.supabase.co`;
const fixtureFile = new URL('.env.commerce-demo.json',root);
const fixture = existsSync(fixtureFile) ? JSON.parse(readFileSync(fixtureFile,'utf8')) : {};
const save = () => writeFileSync(fixtureFile,JSON.stringify(fixture,null,2)+'\n');
async function request(path,{token=service,method='POST',body,expected=[200,201,204],headers={}}={}) {
  const response = await fetch(base+path,{method,headers:{apikey:token===service?backendKey:publishable,...(token===publishable?{}:{Authorization:`Bearer ${token}`}),'Content-Type':'application/json',...headers},body:body===undefined?undefined:JSON.stringify(body)});
  const data = await response.json().catch(()=>null);
  assert.ok(expected.includes(response.status), `${method} ${path}: HTTP ${response.status}: ${JSON.stringify(data)}`);
  return {status:response.status,data};
}
const report = {};
const action = process.argv[2] ?? 'verify';
function writeDemoLogins() {
  mkdirSync(new URL('dist/',root),{recursive:true});
  writeFileSync(new URL('dist/COMPARTS_DEMO_ACCOUNTS.txt',root),[
    'COMPARTS sample accounts — development project only',`Supabase project: ${ref}`,`Backend: ${base}`,'',
    ...['seller','buyer'].flatMap(role=>[`${role.toUpperCase()}: ${fixture[role].email}`,`Password: ${fixture[role].password}`,'']),
    'Use Sign in with these existing accounts; no signup OTP is needed.',
    'Seller: Account > Seller Center > open an order > Mark out for delivery.',
    'Buyer: Orders > open shipped order > Mark as received > submit stars and review notes.',
    'Online payments use Xendit Test Mode. COD and courier updates are entered manually.',
    'These are fictional, preverified demo accounts; they cannot receive verification emails.','',
  ].join('\n'));
}
if (action==='logins') { writeDemoLogins(); report.credentials_file='dist/COMPARTS_DEMO_ACCOUNTS.txt'; }
if (action==='easy-passwords') {
  let updated=0,verified=0;
  for (const name of ['.env.commerce-demo.json','.env.payment-test.json']) {
    const file=new URL(name,root);
    if (!existsSync(file)) continue;
    const accounts=name==='.env.commerce-demo.json'?fixture:JSON.parse(readFileSync(file,'utf8'));
    for (const role of ['seller','buyer','outsider']) {
      const account=accounts[role];
      if (!account?.id) continue;
      const existing=(await request(`/auth/v1/admin/users/${account.id}`,{method:'GET'})).data;
      assert.ok(existing.app_metadata?.rigmarket_test===true && existing.email===account.email,'Expected isolated demo account; no password changed');
      await request(`/auth/v1/admin/users/${account.id}`,{method:'PUT',body:{password:'test123'}});
      account.password='test123';writeFileSync(file,JSON.stringify(accounts,null,2)+'\n');updated++;
      const login=(await request('/auth/v1/token?grant_type=password',{token:publishable,body:{email:account.email,password:account.password}})).data;
      assert.equal(login.user.id,account.id);verified++;
    }
  }
  writeDemoLogins();
  report.updated_demo_accounts=updated;report.verified_password_signins=verified;
}
if (action==='setup') {
  for (const role of ['seller','buyer']) {
    if (fixture[role]?.id) continue;
    const email=`comparts-${role}@example.com`,password='test123';
    const user=(await request('/auth/v1/admin/users',{body:{email,password,email_confirm:true,
      user_metadata:{display_name:role==='seller'?'COMPARTS Sample Seller':'Sample Buyer'},
      app_metadata:{rigmarket_test:true,comparts_demo:true}}})).data;
    fixture[role]={id:user.id,email,password}; save();
  }
  await request('/rest/v1/seller_profiles?on_conflict=id',{headers:{Prefer:'resolution=merge-duplicates'},body:{id:fixture.seller.id,shop_name:'COMPARTS',description:'Sample PC parts shop for demonstrating orders, delivery and reviews.',status:'approved'}});
  const parts=[
    ['cpu','AMD Ryzen 5 7600','AMD',1099500,{Socket:'AM5',Cores:'6 cores / 12 threads'}],
    ['ram','Corsair Vengeance DDR5 32 GB','Corsair',629500,{Capacity:'32 GB (2 × 16 GB)',Speed:'6000 MT/s'}],
    ['storage','WD Black SN770 1 TB NVMe SSD','Western Digital',459500,{Capacity:'1 TB',Interface:'PCIe 4.0 NVMe'}],
    ['peripherals','Keychron C3 Mechanical Keyboard','Keychron',249500,{Layout:'Tenkeyless',Connection:'USB wired'}],
    ['psu','Corsair RM650 650 W Power Supply','Corsair',499500,{Wattage:'650 W',Efficiency:'80 Plus Gold'}],
    ['cooler','DeepCool AK400 CPU Cooler','DeepCool',159500,{Fan:'120 mm',Compatibility:'AM4 / AM5 / LGA1700'}],
  ];
  fixture.products??=[];
  for (const [index,[category,name,brand,price,specs]] of parts.entries()) {
    const id=fixture.products[index]?.id??randomUUID();
    fixture.products[index]={id,name,price}; save();
    await request('/rest/v1/products?on_conflict=id',{headers:{Prefer:'resolution=ignore-duplicates'},body:{
      id,seller_id:fixture.seller.id,category_id:category,name,brand,price_centavos:price,stock:20,condition:'new',status:'published',
      description:`${name}. Sample listing for trying the COMPARTS shopping, cash-on-delivery and delivery-tracking flow.`,
      specifications:specs,warranty:'Sample listing: discuss the seller warranty and return policy before a real purchase.',
    }});
  }
  writeDemoLogins();
  report.accounts_ready=true;report.products=fixture.products.length;report.credentials_file='dist/COMPARTS_DEMO_ACCOUNTS.txt';
}
if (action==='verify-race') {
  const login=async account=>(await request('/auth/v1/token?grant_type=password',{token:publishable,body:{email:account.email,password:account.password}})).data.access_token;
  const legacy=JSON.parse(readFileSync(new URL('.env.payment-test.json',root),'utf8'));
  const tokens=[await login(fixture.buyer),await login(legacy.outsider)];
  const productId=randomUUID();let winners=[];
  await request('/rest/v1/products',{body:{id:productId,seller_id:fixture.seller.id,category_id:'peripherals',name:'Temporary concurrency fixture',brand:'COMPARTS',price_centavos:10000,stock:1,condition:'new',status:'published'}});
  try {
    const results=await Promise.all(tokens.map(async token=>({token,...await request('/functions/v1/commerce-order',{token,expected:[200,409],body:{
      action:'create_cod',product_id:productId,quantity:1,idempotency_key:randomUUID(),expected_unit_price_centavos:10000,
      shipping_address:{recipient:'Sample Buyer',phone:'09171234567',address:'123 Sample Street, Barangay Demo',city:'Quezon City',postal_code:'1100'},
    }})})));
    winners=results.filter(r=>r.status===200);
    assert.equal(winners.length,1);assert.equal(results.filter(r=>r.status===409).length,1);
    const item=(await request(`/rest/v1/products?id=eq.${productId}&select=stock`,{method:'GET'})).data[0];assert.equal(item.stock,0);
    report.last_unit_sold_to_exactly_one_buyer=true;
  } finally {
    await request(`/rest/v1/products?id=eq.${productId}`,{method:'PATCH',body:{status:'archived'}});
    for (const winner of winners) {
      const id=winner.data.order.id;
      await request('/functions/v1/commerce-order',{token:winner.token,body:{action:'cancel',order_id:id}});
      await request(`/rest/v1/order_delivery_events?order_id=eq.${id}`,{method:'DELETE'});
      await request(`/rest/v1/orders?id=eq.${id}`,{method:'DELETE'});
    }
    await request(`/rest/v1/products?id=eq.${productId}`,{method:'DELETE'});
  }
  report.temporary_race_records_removed=true;
}
if (action==='verify-online') {
  const login=(await request('/auth/v1/token?grant_type=password',{token:publishable,body:{email:fixture.buyer.email,password:fixture.buyer.password}})).data.access_token;
  const product=fixture.products[2];
  const before=(await request(`/rest/v1/products?id=eq.${product.id}&select=stock`,{method:'GET'})).data[0].stock;
  const payload={product_id:product.id,quantity:1,idempotency_key:randomUUID(),expected_unit_price_centavos:product.price,
    shipping_address:{recipient:'Sample Buyer',phone:'09171234567',address:'123 Sample Street, Barangay Demo',city:'Quezon City, Metro Manila',postal_code:'1100'}};
  const first=(await request('/functions/v1/checkout-create',{token:login,body:payload})).data.order;
  assert.equal(first.payment_method,'xendit');assert.equal(first.fulfillment,'delivery');assert.equal(first.shipping_address.postal_code,'1100');
  assert.equal(first.status,'payment_pending');assert.ok(first.payment_session_id);
  const replay=(await request('/functions/v1/checkout-create',{token:login,body:payload})).data.order;
  assert.equal(replay.id,first.id);
  const cancelled=(await request('/functions/v1/order-cancel',{token:login,body:{order_id:first.id}})).data.order;
  assert.equal(cancelled.status,'cancelled');
  const after=(await request(`/rest/v1/products?id=eq.${product.id}&select=stock`,{method:'GET'})).data[0].stock;
  assert.equal(after,before);
  report.online_shipping_checkout_and_idempotency=true;report.provider_confirmed_cancellation=true;report.stock_restored=true;
}
if (action==='verify') {
  assert.ok(fixture.buyer&&fixture.seller,'Run setup first');
  const login=async account=>(await request('/auth/v1/token?grant_type=password',{token:publishable,body:{email:account.email,password:account.password}})).data.access_token;
  const buyer=await login(fixture.buyer),seller=await login(fixture.seller);
  const legacy=JSON.parse(readFileSync(new URL('.env.payment-test.json',root),'utf8'));
  const outsider=await login(legacy.outsider);
  const call=(token,body,expected)=>request('/functions/v1/commerce-order',{token,body,expected});
  const shipping={recipient:'Sample Buyer',phone:'09171234567',address:'123 Sample Street, Barangay Demo',city:'Quezon City, Metro Manila',postal_code:'1100'};
  const product=fixture.products[0];
  const stock=async()=> (await request(`/rest/v1/products?id=eq.${product.id}&select=stock`,{method:'GET'})).data[0].stock;
  const before=await stock();
  const payload={action:'create_cod',product_id:product.id,quantity:1,idempotency_key:randomUUID(),expected_unit_price_centavos:product.price,shipping_address:shipping};
  await call('invalid-token',payload,[401]);
  await call(seller,payload,[409]);
  await call(buyer,{...payload,expected_unit_price_centavos:1},[409]);
  await call(buyer,{...payload,shipping_address:{...shipping,postal_code:'x'}},[409]);
  report.invalid_auth_self_purchase_price_and_shipping_rejected=true;
  const [first,replay]=await Promise.all([call(buyer,payload),call(buyer,payload)]);
  const id=first.data.order.id;
  assert.equal(first.data.order.payment_method,'cod');assert.equal(first.data.order.status,'cod_pending');
  assert.equal(replay.data.order.id,id);assert.equal(await stock(),before-1);
  report.concurrent_idempotency_and_stock=true;
  assert.equal((await call(buyer,{...payload,idempotency_key:randomUUID()})).data.order.id,id);
  await call(buyer,{...payload,quantity:2},[409]);
  await call(outsider,{action:'get',order_id:id},[404]);
  const leaked=await request(`/rest/v1/orders?id=eq.${id}&select=id`,{token:outsider,method:'GET'});
  assert.equal(leaked.data.length,0);
  assert.equal((await call(seller,{action:'get',order_id:id})).data.role,'seller');
  await request(`/rest/v1/orders?id=eq.${id}`,{token:buyer,method:'PATCH',body:{status:'paid',fulfillment_status:'delivered'},expected:[403]});
  await request('/rest/v1/rpc/commerce_receive',{token:buyer,body:{p_actor:fixture.buyer.id,p_order:id},expected:[401,403,404]});
  await call(buyer,{action:'dispatch',order_id:id,courier:'Demo Courier',tracking_number:'CP-DEMO-001'},[403]);
  await call(seller,{action:'receive',order_id:id},[403]);
  await call(buyer,{action:'receive',order_id:id},[409]);
  await call(buyer,{action:'review',order_id:id,rating:5,review_notes:'Too early'},[409]);
  report.participant_and_state_guards=true;
  const shipment={action:'dispatch',order_id:id,courier:'Demo Courier',tracking_number:`CP-${id.slice(0,8).toUpperCase()}`};
  assert.equal((await call(seller,shipment)).data.order.fulfillment_status,'shipped');
  await call(seller,shipment);
  await call(buyer,{action:'cancel',order_id:id},[409]);
  const received=(await call(buyer,{action:'receive',order_id:id})).data.order;
  assert.equal(received.fulfillment_status,'delivered');assert.equal(received.status,'paid');
  await call(buyer,{action:'receive',order_id:id});
  const review={action:'review',order_id:id,rating:5,review_notes:'Sample review: item received and the COD delivery flow worked well.'};
  await call(buyer,{...review,rating:6},[409]);
  await call(buyer,review);await call(buyer,review);
  await call(buyer,{...review,rating:4},[409]);
  await call(seller,review,[403]);
  const detail=(await call(buyer,{action:'get',order_id:id})).data;
  assert.deepEqual(detail.events.map(e=>e.event),['placed','shipped','received']);
  assert.equal(detail.review.rating,5);
  const summary=(await request('/rest/v1/rpc/product_review_summary',{token:publishable,body:{p_product:product.id}})).data;
  assert.ok(summary.count>=1);assert.ok(summary.reviews.every(r=>!('buyer_id'in r)&&!('order_id'in r)));
  assert.equal(await stock(),before-1);
  report.dispatch_receipt_cod_payment_and_public_review=true;
  const cancellation={...payload,idempotency_key:randomUUID()};
  const cancelId=(await call(buyer,cancellation)).data.order.id;
  await call(buyer,{action:'cancel',order_id:cancelId});await call(buyer,{action:'cancel',order_id:cancelId});
  assert.equal(await stock(),before-1);
  await call(seller,{...shipment,order_id:cancelId},[409]);
  report.cancellation_restocked_once=true;
  // Leave a ready-to-ship order for the user to dispatch manually in the APK.
  const next=fixture.products[3];
  const pending=(await call(buyer,{...payload,product_id:next.id,expected_unit_price_centavos:next.price,idempotency_key:randomUUID()})).data.order;
  fixture.completed_order_id=id;fixture.pending_order_id=pending.id;save();
  report.completed_order_id=id;report.ready_to_ship_order_id=pending.id;
}
console.log(JSON.stringify(report,null,2));
