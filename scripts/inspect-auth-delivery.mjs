// Read-only email diagnostics. Credentials stay in memory and are never logged.
import './connection-env.mjs';
import {createRequire} from 'node:module';
import {readFileSync,readdirSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const require=createRequire(import.meta.url);
const cache=join(process.env.LOCALAPPDATA??'', 'npm-cache','_npx');
const keyringPath=existsSync(cache)?readdirSync(cache).map(dir=>join(cache,dir,'node_modules','@napi-rs','keyring'))
  .find(dir=>existsSync(join(dir,'package.json'))):undefined;
const {Entry,findCredentials}=keyringPath?require(keyringPath):{};
function normalize(value){
  if(!value)return '';
  if(value.startsWith('go-keyring-base64:'))value=Buffer.from(value.slice('go-keyring-base64:'.length),'base64').toString('utf8');
  if(/^sbp_/.test(value))return value;
  const bytes=[];
  for(let i=0;i<value.length;i++){const c=value.charCodeAt(i);bytes.push(c&255);if(c>>8)bytes.push(c>>8);}
  return Buffer.from(bytes).toString('utf8');
}
let token=process.env.SUPABASE_ACCESS_TOKEN;
if(!token){
  if(!Entry)throw new Error('The installed Windows keyring helper is unavailable. Set SUPABASE_ACCESS_TOKEN through your environment instead.');
  for(const key of ['supabase','access-token','default']){
    try{
      const candidate=normalize(new Entry('Supabase CLI',key).getPassword());
      if(candidate&&/^sbp_/.test(candidate)){token=candidate;break;}
    }catch{ /* Try the supported legacy/profile names only. */ }
    try{
      const credential=findCredentials('Supabase CLI',`Supabase CLI:${key}`).find(c=>c.account===key);
      const candidate=normalize(credential?.password);
      if(/^sbp_/.test(candidate)){token=candidate;break;}
    }catch{}
  }
}
if(!token)throw new Error('Supabase CLI management credential is unavailable.');
const ref=readFileSync(new URL('../supabase/.temp/project-ref',import.meta.url),'utf8').trim();
if(!/^[a-z]{20}$/.test(ref))throw new Error('Invalid linked project reference.');
async function get(path){
  const response=await fetch(`https://api.supabase.com/v1/projects/${ref}/${path}`,{
    headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(30000)});
  if(!response.ok)throw new Error(`Management request failed: HTTP ${response.status}`);
  return response.json();
}
const config=await get('config/auth');
console.log(JSON.stringify({email_config:{
  signup_enabled:!config.disable_signup,email_confirmation_required:!config.mailer_autoconfirm,
  smtp_host:config.smtp_host,smtp_port:config.smtp_port,
  smtp_user_present:!!config.smtp_user,smtp_password_present:!!config.smtp_pass,
  sender_matches_smtp_user:config.smtp_admin_email===config.smtp_user,
  sender_name:config.smtp_sender_name,
  confirmation_template_has_token:String(config.mailer_templates_confirmation_content??'').includes('{{ .Token }}'),
  email_otp_length:config.mailer_otp_length,email_otp_expiry:config.mailer_otp_exp,
}},null,2));
if(process.argv.includes('--smtp-probe')){
  if(config.smtp_host==='smtp.gmail.com'&&!/^[a-z]{16}$/i.test(String(config.smtp_pass??'').replaceAll(' ',''))){
    throw new Error('Management API returns an opaque SMTP secret; no authentication probe was attempted. Use an OTP delivery test.');
  }
  if(!config.smtp_pass||/^(\*+|REDACTED)$/i.test(config.smtp_pass))throw new Error('SMTP credential is masked; no probe attempted.');
  const probe=spawnSync('python',['-c',[
    'import sys,json,smtplib,ssl',
    'c=json.load(sys.stdin)',
    'try:',
    ' s=smtplib.SMTP(c["smtp_host"],int(c["smtp_port"]),timeout=20)',
    ' s.ehlo();s.starttls(context=ssl.create_default_context());s.ehlo()',
    ' code,_=s.login(c["smtp_user"],c["smtp_pass"])',
    ' s.quit();print(json.dumps({"smtp_auth_code":code,"email_sent":False}))',
    'except smtplib.SMTPResponseException as e:',
    ' print(json.dumps({"smtp_auth_code":e.smtp_code,"smtp_error":e.smtp_error.decode("utf-8","replace"),"email_sent":False}))',
    'except Exception as e:',
    ' print(json.dumps({"smtp_probe_error":type(e).__name__,"email_sent":False}))',
  ].join('\n')],{input:JSON.stringify({smtp_host:config.smtp_host,smtp_port:config.smtp_port,smtp_user:config.smtp_user,smtp_pass:config.smtp_pass}),encoding:'utf8',timeout:30000});
  const result=JSON.parse(probe.stdout||'{}');
  if(result.smtp_error)result.smtp_error=result.smtp_error.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi,'[email]');
  console.log(JSON.stringify(result,null,2));
}
const end=new Date(),start=new Date(end.getTime()-90*60*1000);
const query="select timestamp,event_message,log_attributes['error'] as detail from logs where source in ('auth_logs','gotrue_logs') and (event_message ilike '%error%' or event_message ilike '%smtp%') order by timestamp desc limit 20";
const params=new URLSearchParams({sql:query,iso_timestamp_start:start.toISOString(),iso_timestamp_end:end.toISOString()});
const logs=await get(`analytics/endpoints/logs?${params}`);
const redact=value=>String(value??'').replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi,'[email]')
  .replace(/(sbp_|sb_secret_|eyJ)[A-Za-z0-9_.-]+/g,'[credential]').slice(0,1200);
if(logs.error)console.log(JSON.stringify({log_query_error:redact(logs.error)}));
else console.log(JSON.stringify({auth_errors:(logs.result??[]).map(row=>{
  let parsed;try{parsed=JSON.parse(row.event_message);}catch{}
  return {timestamp:row.timestamp,error:redact(row.detail||parsed?.error||parsed?.msg||row.event_message)};
})},null,2));
