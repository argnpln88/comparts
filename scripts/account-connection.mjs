// Explicit account migration. Secrets are read from an ignored local file.
import {readFileSync,writeFileSync,readdirSync,existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {execFileSync,spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import assert from 'node:assert/strict';

const root=new URL('../',import.meta.url);
const read=path=>readFileSync(new URL(path,root),'utf8');
const write=(path,value)=>writeFileSync(new URL(path,root),value);
const cfg=JSON.parse(read('.env.account-connection.json'));
const ref=cfg.SUPABASE_PROJECT_REF;
assert.equal(ref,'qheletzzjnwsjaavbiqc','This handoff is restricted to the requested Comparts project.');
const action=process.argv[2]??'plan';
const migrations=readdirSync(new URL('supabase/migrations/',root)).filter(f=>/^\d+_.*\.sql$/.test(f)).sort();
const functions=readdirSync(new URL('supabase/functions/',root),{withFileTypes:true}).filter(f=>f.isDirectory()&&!f.name.startsWith('_')).map(f=>f.name);
if(action==='plan'){
  console.log(JSON.stringify({target_project:ref,migrations,functions,credentials_present:{
    supabase:!!cfg.SUPABASE_ACCESS_TOKEN,xendit_test:cfg.XENDIT_SECRET_KEY.startsWith('xnd_development_'),
    callback:!!cfg.XENDIT_CALLBACK_TOKEN,business:!!cfg.XENDIT_BUSINESS_ID,smtp:!!cfg.SMTP_PASSWORD,
  },active_project:read('supabase/.temp/project-ref').trim(),changes_applied:false},null,2));
  process.exit(0);
}
assert.ok(/^sbp_[A-Za-z0-9_-]+$/.test(cfg.SUPABASE_ACCESS_TOKEN),'Enter a new-account Supabase access token in the ignored connection file.');
const env={...process.env,SUPABASE_ACCESS_TOKEN:cfg.SUPABASE_ACCESS_TOKEN};
async function manage(path,{method='GET',body}={}){
  const r=await fetch(`https://api.supabase.com/v1/projects/${ref}${path}`,{method,
    headers:{Authorization:`Bearer ${cfg.SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'},
    body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(120000)});
  if(!r.ok){
    const failure=await r.json().catch(()=>({}));
    const reason=String(failure.message??failure.error??'').replace(/sbp_[A-Za-z0-9_-]+/g,'[hidden]').slice(0,350);
    throw Error(`Supabase management ${method} ${path}: HTTP ${r.status} ${reason}`);
  }
  const payload=await r.text();
  return payload?JSON.parse(payload):null;
}
const project=await manage('');
assert.equal(project.id??project.ref,ref);
assert.equal(project.organization_id,'bpjecyjflukkyewrkcho','Unexpected organization.');
const sql=async query=>manage('/database/query',{method:'POST',body:{query}});
const literal=s=>`'${s.replaceAll("'","''")}'`;
async function keys(){
  const result=await manage('/api-keys?reveal=true');
  const service=result.find(k=>k.name==='service_role')?.api_key;
  const secret=result.find(k=>k.type==='secret'&&k.name==='default')?.api_key??service;
  const publishable=result.find(k=>k.type==='publishable')?.api_key??result.find(k=>k.name==='anon')?.api_key;
  assert.ok(service&&publishable,'Existing Supabase keys unavailable.');
  return {service,secret,publishable};
}
async function backend(name,body){
  const k=await keys();
  const r=await fetch(`https://${ref}.supabase.co/functions/v1/${name}`,{method:'POST',headers:{
    apikey:k.secret,Authorization:`Bearer ${k.service}`,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(120000)});
  if(!r.ok)throw Error(`Backend ${name}: HTTP ${r.status}`);
  return r.json();
}
function cli(args){
  try{return execFileSync('cmd.exe',['/d','/c','npx.cmd','--yes','supabase',...args],{cwd:root,env,encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:600000});}
  catch{throw Error('Supabase CLI command failed; credential values suppressed.');}
}
if(action==='audit'){
  const auth=await manage('/config/auth');
  const deployed=await manage('/functions');
  console.log(JSON.stringify({project:project.name,ref,
    database:await sql("select tablename,rowsecurity from pg_tables where schemaname='public' order by tablename"),
    functions:deployed.map(f=>({name:f.name,status:f.status,verify_jwt:f.verify_jwt})),
    auth:{confirmation_required:!auth.mailer_autoconfirm,otp_length:auth.mailer_otp_length,otp_expiry:auth.mailer_otp_exp,
      smtp_host:auth.smtp_host,sender:auth.smtp_admin_email,smtp_configured:!!auth.smtp_pass,
      confirmation_has_token:!!auth.mailer_templates_confirmation_content?.includes('{{ .Token }}'),
      recovery_has_token:!!auth.mailer_templates_recovery_content?.includes('{{ .Token }}')}
  },null,2));
}else if(action==='database'){
  await sql('create schema if not exists supabase_migrations; create table if not exists supabase_migrations.schema_migrations(version text primary key,statements text[],name text);');
  const applied=await sql('select version from supabase_migrations.schema_migrations');
  for(const file of migrations){
    const [version,...parts]=file.replace(/\.sql$/,'').split('_');
    if(applied.some(m=>m.version===version))continue;
    const body=read(`supabase/migrations/${file}`).replace(/^\s*begin;\s*$/im,'').replace(/commit;\s*$/i,'');
    await sql(`begin;\n${body}\ninsert into supabase_migrations.schema_migrations(version,name,statements) values(${literal(version)},${literal(parts.join('_'))},ARRAY[${literal(body)}]);\ncommit;`);
    console.log(`Applied ${file}`);
  }
}else if(action==='otp-test'){
  const file='.env.auth-connection-test.json';
  const fixture=existsSync(new URL(file,root))?JSON.parse(read(file)):{project_ref:ref,email:'aragonpilon88+comparts-connection@gmail.com',password:randomBytes(24).toString('base64url')};
  assert.equal(fixture.project_ref,ref);
  if(fixture.request_started){
    console.log(JSON.stringify({email_request_already_attempted:true,http_status:fixture.http_status??null,accepted:fixture.accepted??false,error_code:fixture.error_code??null,inbox_delivery_verified:fixture.inbox_delivery_verified===true}));
  }else{
    fixture.request_started=new Date().toISOString();write(file,JSON.stringify(fixture,null,2)+'\n');
    const k=await keys();
    const r=await fetch(`https://${ref}.supabase.co/auth/v1/signup?redirect_to=${encodeURIComponent('com.rigmarket.rigmarket://auth/callback')}`,{method:'POST',headers:{apikey:k.publishable,'Content-Type':'application/json'},
      body:JSON.stringify({email:fixture.email,password:fixture.password,data:{display_name:'COMPARTS email connection test'}}),signal:AbortSignal.timeout(30000)});
    const data=await r.json();
    Object.assign(fixture,{http_status:r.status,accepted:r.ok,user_id:data.user?.id??data.id??null,error_code:data.error_code??data.code??null});
    write(file,JSON.stringify(fixture,null,2)+'\n');
    console.log(JSON.stringify({http_status:r.status,accepted:r.ok,error_code:fixture.error_code,inbox_delivery_verified:false}));
  }
}else if(action==='auth-check'){
  const auth=await manage('/config/auth');
  const normalize=value=>String(value??'').trim().replaceAll('\r\n','\n');
  console.log(JSON.stringify({smtp_configured:!!auth.smtp_pass,sender:auth.smtp_admin_email,
    otp_length:auth.mailer_otp_length,otp_expiry:auth.mailer_otp_exp,
    confirmation_matches:normalize(auth.mailer_templates_confirmation_content)===normalize(read('supabase/templates/confirmation.html')),
    recovery_matches:normalize(auth.mailer_templates_recovery_content)===normalize(read('supabase/templates/recovery.html')),
    callback_allowed:(auth.uri_allow_list??'').split(',').includes('com.rigmarket.rigmarket://auth/callback')},null,2));
}else if(action==='catalog-check'){
  const k=await keys();
  const get=async(path)=>{
    const r=await fetch(`https://${ref}.supabase.co/rest/v1/${path}`,{headers:{apikey:k.publishable},signal:AbortSignal.timeout(30000)});
    assert.ok(r.ok,`Public catalog request failed: ${r.status}`);return r.json();
  };
  const categories=await get('categories?select=id,name');
  const products=await get('products?select=id,category_id,image_url,image_is_illustration,seller_profiles(shop_name,logo_url)&status=eq.published');
  const counts=Object.fromEntries(categories.map(c=>[c.name,products.filter(p=>p.category_id===c.id).length]));
  assert.equal(categories.length,10);assert.ok(Object.values(counts).every(n=>n>=3));
  assert.ok(products.every(p=>p.image_is_illustration&&p.image_url.startsWith(`https://${ref}.supabase.co/storage/`)&&p.seller_profiles?.shop_name));
  const query='products?select=id&status=eq.published&order=created_at.desc,id.desc&limit=21&offset=';
  const first=await get(query+'0'),second=await get(query+'20');
  assert.equal(first.length,21);assert.equal(second.length,products.length-20);
  assert.ok(!first.slice(0,20).some(p=>second.some(q=>q.id===p.id)));
  const mobile=JSON.parse(read('config/mobile.dev.json'));
  assert.equal(mobile.SUPABASE_URL,`https://${ref}.supabase.co`);assert.equal(mobile.SUPABASE_PUBLISHABLE_KEY,k.publishable);
  const report={checked_at:new Date().toISOString(),project_ref:ref,total_published_items:products.length,category_counts:counts,
    mobile_connection_matches:true,public_catalog_and_seller_joins:true,all_images_on_active_project:true,
    pagination:{first_page:20,second_page:second.length,overlap:false}};
  write('build/connection-catalog-verification.json',JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
}else if(action==='smtp-probe'){
  const auth=await manage('/config/auth');
  if(auth.smtp_host==='smtp.gmail.com'&&!/^[a-z]{16}$/i.test(String(auth.smtp_pass??'').replaceAll(' ',''))){
    console.log(JSON.stringify({smtp_configured:!!auth.smtp_pass,plaintext_credential_available:false,smtp_auth_probe_performed:false,note:'Management API returns an opaque SMTP secret. Use the saved configuration for an OTP delivery test.'}));
    process.exit(0);
  }
  assert.ok(auth.smtp_pass&&!/^(\*+|REDACTED)$/i.test(auth.smtp_pass),'SMTP secret is not available for the authentication probe.');
  const probe=spawnSync('python',['-c',[
    'import sys,json,smtplib,ssl',
    'c=json.load(sys.stdin)',
    'phase="connect"',
    'try:',
    ' s=smtplib.SMTP(c["smtp_host"],int(c["smtp_port"]),timeout=20)',
    ' phase="starttls";s.ehlo();s.starttls(context=ssl.create_default_context());s.ehlo()',
    ' phase="login"',
    ' code,_=s.login(c["smtp_user"],c["smtp_pass"])',
    ' print(json.dumps({"smtp_auth_code":code,"email_sent":False}));s.close()',
    'except smtplib.SMTPResponseException as e:',
    ' print(json.dumps({"smtp_auth_code":e.smtp_code,"phase":phase,"email_sent":False}))',
    'except Exception as e:',
    ' print(json.dumps({"smtp_probe_error":type(e).__name__,"phase":phase,"email_sent":False}))',
  ].join('\n')],{input:JSON.stringify({smtp_host:auth.smtp_host,smtp_port:auth.smtp_port,smtp_user:auth.smtp_user,smtp_pass:auth.smtp_pass}),encoding:'utf8',timeout:30000});
  console.log(probe.stdout||'SMTP probe returned no status.');
}else if(action==='sql-checks'||action==='sql-permissions'){
  for(const file of action==='sql-permissions'?['commerce_permissions.sql']:['commerce_permissions.sql','payments.sql']){
    await sql(read(`supabase/tests/${file}`));
    console.log(`Passed ${file}`);
  }
}else if(action==='provider-probe'){
  assert.ok(cfg.XENDIT_SECRET_KEY.startsWith('xnd_development_'),'Test key required.');
  const provider=async(path,method='GET',body)=>{
    const r=await fetch(`https://api.xendit.co${path}`,{method,headers:{Authorization:`Basic ${Buffer.from(cfg.XENDIT_SECRET_KEY+':').toString('base64')}`,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
    const data=await r.json();
    if(!r.ok)throw Error(`Xendit test request: HTTP ${r.status} ${data.error_code??''}`);
    return data;
  };
  let session=cfg.CONNECTION_PROBE_SESSION_ID?await provider(`/sessions/${cfg.CONNECTION_PROBE_SESSION_ID}`):null;
  if(!session){
    assert.ok(!cfg.CONNECTION_PROBE_STARTED,'An earlier probe result is uncertain; inspect Xendit before creating another.');
    cfg.CONNECTION_PROBE_STARTED=new Date().toISOString();write('.env.account-connection.json',JSON.stringify(cfg,null,2)+'\n');
    session=await provider('/sessions','POST',{reference_id:`comparts-connection-${Date.now()}`,session_type:'PAY',mode:'PAYMENT_LINK',capture_method:'AUTOMATIC',allow_save_payment_method:'DISABLED',currency:'PHP',country:'PH',amount:100,
      customer:{reference_id:`connection-${Date.now()}`,type:'INDIVIDUAL',email:'comparts-connection@example.com',individual_detail:{given_names:'COMPARTS',surname:'Test'}},
      description:'COMPARTS connection check - TEST ONLY - no real charge',expires_at:new Date(Date.now()+1800000).toISOString()});
    assert.ok(/^[a-f0-9]{24}$/.test(session.business_id));
    cfg.CONNECTION_PROBE_SESSION_ID=session.payment_session_id;cfg.XENDIT_BUSINESS_ID=session.business_id;
    write('.env.account-connection.json',JSON.stringify(cfg,null,2)+'\n');
  }
  if(session.status==='ACTIVE')session=await provider(`/sessions/${session.payment_session_id}/cancel`,'POST',{});
  console.log(JSON.stringify({provider_test_connection:true,business_id_recorded:!!cfg.XENDIT_BUSINESS_ID,probe_session:cfg.CONNECTION_PROBE_SESSION_ID,probe_status:session.status,no_payment_collected:true}));
}else if(action==='auth'){
  const current=await manage('/config/auth');
  const callback='com.rigmarket.rigmarket://auth/callback';
  const allow=[...new Set([...(current.uri_allow_list??'').split(',').filter(Boolean),callback])].join(',');
  const settings={external_email_enabled:true,disable_signup:false,mailer_autoconfirm:false,
    mailer_otp_length:6,mailer_otp_exp:600,uri_allow_list:allow,
    mailer_subjects_confirmation:'Verify your COMPARTS account',mailer_subjects_recovery:'Reset your COMPARTS password',
    mailer_templates_confirmation_content:read('supabase/templates/confirmation.html'),
    mailer_templates_recovery_content:read('supabase/templates/recovery.html')};
  if(cfg.SMTP_PASSWORD)Object.assign(settings,{smtp_host:cfg.SMTP_HOST,smtp_port:String(cfg.SMTP_PORT),
    smtp_user:cfg.SMTP_USER,smtp_pass:cfg.SMTP_PASSWORD.replaceAll(' ',''),smtp_admin_email:cfg.SMTP_USER,smtp_sender_name:cfg.SMTP_SENDER_NAME});
  await manage('/config/auth',{method:'PATCH',body:settings});
  const check=await manage('/config/auth');
  assert.equal(check.mailer_otp_length,6);assert.equal(check.mailer_otp_exp,600);assert.equal(check.mailer_autoconfirm,false);
  assert.equal(check.mailer_templates_confirmation_content,settings.mailer_templates_confirmation_content);
  assert.equal(check.mailer_templates_recovery_content,settings.mailer_templates_recovery_content);
  console.log(JSON.stringify({auth_configured:true,smtp_configured:!!check.smtp_pass,inbox_delivery_verified:false}));
}else if(action==='secrets'||action==='secrets-known'){
  assert.ok(/^xnd_development_/.test(cfg.XENDIT_SECRET_KEY),'A Xendit TEST secret is required.');
  assert.match(cfg.XENDIT_BUSINESS_ID,/^[a-f0-9]{24}$/i,'The new Xendit business ID is required.');
  if(action==='secrets')assert.ok(cfg.XENDIT_CALLBACK_TOKEN,'The new Xendit callback token is required.');
  if(!cfg.RECONCILIATION_JOB_SECRET){cfg.RECONCILIATION_JOB_SECRET=randomBytes(32).toString('hex');write('.env.account-connection.json',JSON.stringify(cfg,null,2)+'\n');}
  const names=['XENDIT_SECRET_KEY','XENDIT_BUSINESS_ID','RECONCILIATION_JOB_SECRET',...(cfg.XENDIT_CALLBACK_TOKEN?['XENDIT_CALLBACK_TOKEN']:[])];
  await manage('/secrets',{method:'POST',body:[...names.map(name=>({name,value:cfg[name]})),{name:'XENDIT_ENV',value:'test'}]});
  console.log('Test payment secrets configured in the new Supabase project.');
}else if(action==='deploy'){
  cli(['functions','deploy',...functions,'--project-ref',ref,'--use-api']);
  const deployed=await manage('/functions');
  for(const name of functions)assert.ok(deployed.some(f=>f.name===name&&f.status==='ACTIVE'),`${name} is not active.`);
  console.log(JSON.stringify({deployed_functions:functions}));
}else if(action==='health'){
  console.log(JSON.stringify(await backend('payment-admin',{action:'health'}),null,2));
}else if(action==='schedule'){
  console.log(JSON.stringify(await backend('payment-admin',{action:'configure-schedule'})));
}else if(action==='schedule-status'){
  console.log(JSON.stringify({jobs:await sql("select jobname,schedule,active from cron.job where jobname='rigmarket-payment-reconcile'"),recent_responses:await sql('select status_code,timed_out,error_msg,created from net._http_response order by created desc limit 3')},null,2));
}else if(action==='activate'){
  const health=await backend('payment-admin',{action:'health'});
  assert.ok(health.database_ready&&health.test_secret_configured&&health.business_id_configured&&health.scheduler_secret_configured&&!health.config_error,'New backend is not ready; active project retained.');
  const auth=await manage('/config/auth');
  assert.ok(auth.mailer_otp_length===6&&auth.mailer_otp_exp===600&&!auth.mailer_autoconfirm,'Expected OTP configuration is missing.');
  const k=await keys();
  const previous=read('supabase/.temp/project-ref').trim();
  if(previous!==ref){
    const archive=`.env.account-backup-${previous}.json`;
    assert.ok(!existsSync(new URL(archive,root)),'An account backup already exists; inspect it before switching again.');
    const backup={project_ref:previous};
    for(const file of ['config/mobile.dev.json','.env.payment-test.json','.env.commerce-demo.json','dist/COMPARTS_DEMO_ACCOUNTS.txt']){
      if(existsSync(new URL(file,root)))backup[file]=read(file);
    }
    write(archive,JSON.stringify(backup,null,2)+'\n');
    for(const file of ['.env.payment-test.json','.env.commerce-demo.json'])write(file,JSON.stringify({project_ref:ref},null,2)+'\n');
    write('dist/COMPARTS_DEMO_ACCOUNTS.txt','New account deployment in progress. Demo accounts have not been provisioned in this project yet.\n');
  }
  // Project-scoped tokens cannot be used with `supabase login` (user scope only).
  // The project wrapper and helper scripts load this token for their own process.
  write('supabase/.temp/project-ref',ref+'\n');
  write('config/mobile.dev.json',JSON.stringify({SUPABASE_URL:`https://${ref}.supabase.co`,SUPABASE_PUBLISHABLE_KEY:k.publishable},null,2)+'\n');
  console.log(JSON.stringify({active_project:ref,previous_project:previous,private_keys_in_mobile_config:false,webhook_setup_pending:!health.webhook_token_configured}));
}else if(action==='run'){
  const script=process.argv[3];
  assert.ok(['payment-dev.mjs','commerce-dev.mjs','sample-media.mjs','catalog-delivery-update.mjs','inspect-auth-delivery.mjs','check-auth-email.mjs'].includes(script));
  assert.equal(read('supabase/.temp/project-ref').trim(),ref,'Activate the verified project first.');
  execFileSync(process.execPath,[fileURLToPath(new URL(`scripts/${script}`,root)),...process.argv.slice(4)],{cwd:root,env,stdio:'inherit',timeout:600000});
}else throw Error('Unknown action. Use plan, audit, database, auth, secrets, deploy, health, schedule, activate, or run.');
