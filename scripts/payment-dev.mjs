// Development provisioning/verification. Never prints or persists backend API keys.
import './connection-env.mjs';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { randomUUID } from 'node:crypto';

const root = new URL('../', import.meta.url);
const ref = readFileSync(new URL('supabase/.temp/project-ref', root), 'utf8').trim();
if (!/^[a-z0-9]+$/.test(ref)) throw new Error('Invalid project reference');
const keys = JSON.parse(execFileSync('cmd.exe', ['/d', '/c', `npx.cmd --yes supabase projects api-keys --project-ref ${ref} --reveal --output json`], { cwd: root, encoding: 'utf8' }));
const service = keys.find(k => k.name === 'service_role')?.api_key;
const backendKey = keys.find(k => k.type === 'secret' && k.name === 'default')?.api_key;
const publishable = keys.find(k => k.type === 'publishable')?.api_key ?? keys.find(k => k.name === 'anon')?.api_key;
if (!service || !publishable) throw new Error('Project API keys could not be obtained');
const base = `https://${ref}.supabase.co`;
const report = {};
async function request(path, { token = service, method = 'POST', body, expected = [200,201,204], headers = {} } = {}) {
  const response = await fetch(base + path, { method, headers: { apikey: token === service ? backendKey ?? service : publishable, Authorization: `Bearer ${token}`, 'Content-Type':'application/json', ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
  const data = await response.json().catch(() => null);
  if (!expected.includes(response.status)) throw new Error(`${path}: HTTP ${response.status}: ${JSON.stringify(data)}`);
  return { status: response.status, data };
}
const action = process.argv[2] ?? 'health';
if (action === 'rename-shop') {
  const fixture = JSON.parse(readFileSync(new URL('.env.payment-test.json', root), 'utf8'));
  const path = `/rest/v1/seller_profiles?id=eq.${encodeURIComponent(fixture.seller.id)}`;
  const current = (await request(`${path}&select=shop_name`, { method:'GET' })).data;
  if (current.length !== 1 || !['RigMarket test shop', 'COMPARTS test shop', 'COMPARTS'].includes(current[0].shop_name)) {
    throw new Error('Expected development shop was not found; no shop changed');
  }
  report.shop = (await request(`${path}&select=shop_name`, { method:'PATCH', headers:{ Prefer:'return=representation' }, body:{ shop_name:'COMPARTS' } })).data;
}
if (action === 'probe') report.probe = (await request('/functions/v1/payment-admin', { body:{ action:'probe' } })).data;
if (action === 'inspect-session') report.session = (await request('/functions/v1/payment-admin', { body:{ action,session_id:process.argv[3] } })).data;
if (action === 'reconcile-order') report.order = (await request('/functions/v1/payment-admin', { body:{ action,order_id:process.argv[3] } })).data;
if (action === 'health' || action === 'setup') {
  report.health = (await request('/functions/v1/payment-admin', { body:{ action:'health' } })).data;
}
if (action === 'setup') {
  writeFileSync(new URL('config/mobile.dev.json', root), JSON.stringify({ SUPABASE_URL:base, SUPABASE_PUBLISHABLE_KEY:publishable }, null, 2) + '\n');
  report.mobile_configured = true;
  report.schedule = (await request('/functions/v1/payment-admin', { body:{ action:'configure-schedule' } })).data;
  const file = new URL('.env.payment-test.json', root);
  const fixture = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {};
  for (const role of ['seller', 'buyer', 'outsider']) {
    if (fixture[role]?.id) continue;
    const email = `rigmarket-demo-${role}@example.com`, password = 'test123';
    const result = (await request('/auth/v1/admin/users', { body: { email, password, email_confirm:true,
      user_metadata:{ display_name:`COMPARTS test ${role}` }, app_metadata:{ rigmarket_test:true } } })).data;
    fixture[role] = { id: result.id, email, password };
    writeFileSync(file, JSON.stringify(fixture,null,2) + '\n');
  }
  await request('/rest/v1/seller_profiles?on_conflict=id', { headers:{ Prefer:'resolution=merge-duplicates' }, body:{ id:fixture.seller.id,shop_name:'COMPARTS',description:'Development listings only. No real products or payouts.',status:'approved' } });
  fixture.product_id ??= randomUUID();
  fixture.race_product_id ??= randomUUID();
  writeFileSync(file,JSON.stringify(fixture,null,2)+'\n');
  for (const [id,name,stock] of [[fixture.product_id,'Xendit test item — no real product',20],[fixture.race_product_id,'Inventory test item — no real product',1]]) {
    // Ignore duplicates so reruns do not reset inventory already reserved by a checkout.
    await request('/rest/v1/products?on_conflict=id', { headers:{ Prefer:'resolution=ignore-duplicates' }, body:{ id,seller_id:fixture.seller.id,category_id:'peripherals',name,brand:'COMPARTS TEST',description:'Test payment demonstration only. No real charge, product delivery or seller settlement.',price_centavos:10000,condition:'new',stock,status:'published',warranty:'Demonstration only',specifications:{Environment:'Xendit Test Mode'} } });
  }
  report.demo_accounts_created = true;
  report.demo_credentials_file = '.env.payment-test.json';
}
if (action === 'race') {
  const fixture = JSON.parse(readFileSync(new URL('.env.payment-test.json',root),'utf8'));
  const before = (await request(`/rest/v1/products?id=eq.${fixture.race_product_id}&select=stock`,{method:'GET'})).data[0].stock;
  if (before !== 1) throw new Error('Inventory race fixture must have one unreserved unit');
  const results = await Promise.all(['buyer','outsider'].map(role => request('/rest/v1/rpc/payment_reserve',{
    body:{p_buyer:fixture[role].id,p_product:fixture.race_product_id,p_quantity:1,p_key:randomUUID(),p_expected_unit:10000},expected:[200,400],
  })));
  const won = results.filter(r => r.status===200), lost = results.filter(r => r.status===400);
  if (won.length!==1 || lost.length!==1) throw new Error('Final unit race was not exclusive');
  const id = won[0].data.order.id;
  // These are DB-only reservations: no provider session was created, so release is safe.
  await request('/rest/v1/rpc/payment_apply',{body:{p_order:id,p_state:'failed',p_error:'DB concurrency test: no provider session requested'}});
  await request('/rest/v1/rpc/payment_apply',{body:{p_order:id,p_state:'failed'}});
  const after = (await request(`/rest/v1/products?id=eq.${fixture.race_product_id}&select=stock`,{method:'GET'})).data[0].stock;
  if (after!==before) throw new Error('Stock release was not idempotent');
  report.concurrent_last_unit_exclusive = true;
  report.duplicate_release_safe = true;
}
if (action === 'verify') {
  const fixture = JSON.parse(readFileSync(new URL('.env.payment-test.json',root),'utf8'));
  const productId = process.argv[4] === 'inventory' ? fixture.race_product_id : fixture.product_id;
  const login = async role => (await request('/auth/v1/token?grant_type=password',{token:publishable,body:{email:fixture[role].email,password:fixture[role].password}})).data.access_token;
  const buyerRole = process.argv[3] ?? 'buyer';
  const buyer = await login(buyerRole), outsider = await login(buyerRole === 'buyer' ? 'outsider' : 'buyer'), seller = await login('seller');
  report.buyer_login = true;
  const forged = await request('/functions/v1/checkout-quote',{token:'forged',body:{product_id:productId,quantity:1},expected:[401]});
  report.forged_token_rejected = forged.status === 401;
  const own = await request('/functions/v1/checkout-quote',{token:seller,body:{product_id:productId,quantity:1},expected:[409]});
  report.self_purchase_rejected = own.status === 409;
  const quote = (await request('/functions/v1/checkout-quote',{token:buyer,body:{product_id:productId,quantity:1}})).data;
  const checkoutBody = {product_id:productId,quantity:1,idempotency_key:randomUUID(),expected_unit_price_centavos:quote.unit_price_centavos};
  const wrongPrice = await request('/functions/v1/checkout-create',{token:buyer,body:{...checkoutBody,expected_unit_price_centavos:1},expected:[409,503]});
  report.changed_price_rejected = wrongPrice.status === 409;
  const created = await request('/functions/v1/checkout-create',{token:buyer,body:checkoutBody,expected:[200,202,422,503]});
  report.checkout_http = created.status;
  report.checkout_status = created.data?.order?.status;
  report.checkout_error = created.data?.error;
  if (created.data?.order) {
    fixture.order_ids = [...new Set([...(fixture.order_ids ?? []), fixture.last_order_id, created.data.order.id].filter(Boolean))];
    fixture.last_order_id = created.data.order.id;
    writeFileSync(new URL('.env.payment-test.json',root),JSON.stringify(fixture,null,2)+'\n');
    report.order_id = fixture.last_order_id;
    const replay = (await request('/functions/v1/checkout-create',{token:buyer,body:checkoutBody})).data;
    report.idempotency_verified = replay.order.id === fixture.last_order_id;
    const leaked = await request(`/rest/v1/orders?id=eq.${fixture.last_order_id}&select=id`,{token:outsider,method:'GET'});
    report.cross_buyer_read_blocked = leaked.data.length === 0;
    report.cross_buyer_function_blocked = (await request('/functions/v1/checkout-status',{token:outsider,body:{order_id:fixture.last_order_id},expected:[404]})).status === 404;
    report.direct_paid_write_blocked = (await request(`/rest/v1/orders?id=eq.${fixture.last_order_id}`,{token:buyer,method:'PATCH',body:{status:'paid'},expected:[401,403]})).status === 403;
    report.direct_payment_rpc_blocked = (await request('/rest/v1/rpc/payment_apply',{token:buyer,body:{p_order:fixture.last_order_id,p_state:'paid'},expected:[401,403,404]})).status !== 200;
    report.refund_admin_required = (await request('/functions/v1/refund-create',{token:buyer,body:{order_id:fixture.last_order_id},expected:[403]})).status === 403;
    const checked = (await request('/functions/v1/checkout-status',{token:buyer,body:{order_id:fixture.last_order_id}})).data;
    report.status_refresh = checked.order.status;
    if (created.data.order.payment_link_url) {
      report.hosted_checkout_url = created.data.order.payment_link_url;
    }
  }
  report.webhook_bad_token_rejected = (await request('/functions/v1/xendit-webhook',{body:{},expected:[401]})).status === 401;
  report.scheduler_bad_token_rejected = (await request('/functions/v1/payment-reconcile',{body:{},expected:[401]})).status === 401;
}
if (action === 'cancel-last') {
  const fixture = JSON.parse(readFileSync(new URL('.env.payment-test.json',root),'utf8'));
  const role = process.argv[3] ?? 'buyer';
  const login = (await request('/auth/v1/token?grant_type=password',{token:publishable,body:{email:fixture[role].email,password:fixture[role].password}})).data;
  const result = (await request('/functions/v1/order-cancel',{token:login.access_token,body:{order_id:fixture.last_order_id}})).data;
  report.cancelled_order = result.order.id;
  report.provider_confirmed_state = result.order.status;
  const replay = (await request('/functions/v1/order-cancel',{token:login.access_token,body:{order_id:fixture.last_order_id}})).data;
  report.repeated_cancellation_safe = replay.order.status === result.order.status;
}
console.log(JSON.stringify(report,null,2));
