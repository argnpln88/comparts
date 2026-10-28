// Inspect pending non-fixture registration and optionally resend its verification.
import './connection-env.mjs';
// API keys stay in memory; no passwords or OTPs are printed.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
const emailIndex = process.argv.indexOf('--email');
const requestedEmail = emailIndex >= 0 ? process.argv[emailIndex + 1]?.trim().toLowerCase() : null;
if ((process.argv.includes('--resend') || process.argv.includes('--recover')) && (!requestedEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(requestedEmail))) {
  throw new Error('Sending requires an explicit --email address. No email was sent.');
}
if (process.argv.includes('--resend') && process.argv.includes('--recover')) {
  throw new Error('Choose one email purpose. No email was sent.');
}
const root = new URL('../', import.meta.url);
const ref = readFileSync(new URL('supabase/.temp/project-ref', root), 'utf8').trim();
if (!/^[a-z0-9]+$/.test(ref)) throw new Error('Invalid project reference');
const keys = JSON.parse(execFileSync('cmd.exe', ['/d','/c',`npx.cmd --yes supabase projects api-keys --project-ref ${ref} --reveal --output json`], {cwd:root,encoding:'utf8'}));
const service = keys.find(k => k.name === 'service_role')?.api_key;
const publishable = keys.find(k => k.type === 'publishable')?.api_key ?? keys.find(k => k.name === 'anon')?.api_key;
const base = `https://${ref}.supabase.co`;
const usersResponse = await fetch(`${base}/auth/v1/admin/users?per_page=1000`, {headers:{apikey:service,Authorization:`Bearer ${service}`}});
if (!usersResponse.ok) throw new Error(`Account inspection failed: ${usersResponse.status}`);
const matchedAccounts = (await usersResponse.json()).users.filter(user => !user.app_metadata?.rigmarket_test && (!requestedEmail || user.email?.toLowerCase() === requestedEmail));
const accounts = matchedAccounts.filter(user => !user.email_confirmed_at);
const report = {pending_accounts:accounts.length,target_explicit:!!requestedEmail};
if (requestedEmail) {
  report.registered_accounts = matchedAccounts.length;
  report.confirmed_accounts = matchedAccounts.filter(user => !!user.email_confirmed_at).length;
  if (matchedAccounts.length === 1) {
    report.email_verified_at = matchedAccounts[0].email_confirmed_at ?? null;
    report.recovery_last_requested = matchedAccounts[0].recovery_sent_at ?? null;
    if (matchedAccounts[0].email_confirmed_at) {
      report.signup_note = 'This account is already verified. Use password sign-in; signup confirmation is no longer pending.';
    }
  }
}
if (process.argv.includes('--connection')) {
  const settingsResponse = await fetch(`${base}/auth/v1/settings`, {headers:{apikey:publishable}});
  const settings = await settingsResponse.json();
  report.connection = {
    host:new URL(base).host,
    auth_settings_http:settingsResponse.status,
    email_provider:settings.external?.email ?? null,
    email_autoconfirm:settings.mailer_autoconfirm ?? null,
  };
  const mobile = JSON.parse(readFileSync(new URL('config/mobile.dev.json',root),'utf8'));
  report.connection.mobile_url_matches = mobile.SUPABASE_URL?.replace(/\/$/,'') === base;
  report.connection.mobile_key_matches = mobile.SUPABASE_PUBLISHABLE_KEY === publishable;
}
if (process.argv.includes('--recover')) {
  if (matchedAccounts.length !== 1) throw new Error('Exactly one matching account is required for the recovery test. No email was sent.');
  const result = await fetch(`${base}/auth/v1/recover?redirect_to=${encodeURIComponent('com.rigmarket.rigmarket://auth/callback')}`, {
    method:'POST',headers:{apikey:publishable,'Content-Type':'application/json'},body:JSON.stringify({email:requestedEmail}),
  });
  const response = await result.json().catch(() => ({}));
  report.recovery_http = result.status;
  report.error_code = response.error_code ?? response.code ?? null;
  report.message = String(response.msg ?? response.message ?? response.error_description ?? '').replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi,'[email]');
  report.note = result.ok ? 'Supabase accepted the recovery request; no password was changed. Inbox delivery still needs verification.' : 'Supabase rejected the recovery request.';
}
if (accounts.length === 1) {
  report.email = accounts[0].email.replace(/(^.).*(@.*$)/,'$1***$2');
  report.confirmation_last_requested = accounts[0].confirmation_sent_at;
  if (process.argv.includes('--resend')) {
    const result = await fetch(`${base}/auth/v1/resend?redirect_to=${encodeURIComponent('com.rigmarket.rigmarket://auth/callback')}`, {
      method:'POST',headers:{apikey:publishable,'Content-Type':'application/json'},body:JSON.stringify({type:'signup',email:accounts[0].email}),
    });
    const response = await result.json().catch(() => ({}));
    report.resend_http = result.status;
    report.error_code = response.error_code ?? response.code ?? null;
    report.message = String(response.msg ?? response.message ?? response.error_description ?? '').replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi,'[email]');
    report.note = result.ok ? 'Supabase accepted the resend; inbox delivery still needs verification.' : 'Supabase rejected the resend.';
  }
}
console.log(JSON.stringify(report,null,2));
