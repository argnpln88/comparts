begin;
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

create function public.payment_schedule(p_url text,p_secret text) returns void
language plpgsql security definer set search_path='' as $$
declare secret_id uuid; old_job bigint;
begin
  if p_url !~ '^https://[a-z0-9]+\.supabase\.co/functions/v1/payment-reconcile$' or char_length(p_secret)<32 then
    raise exception 'Invalid payment schedule configuration';
  end if;
  select id into secret_id from vault.secrets where name='rigmarket_payment_job_secret';
  if secret_id is null then perform vault.create_secret(p_secret,'rigmarket_payment_job_secret');
  else perform vault.update_secret(secret_id,p_secret); end if;
  select id into secret_id from vault.secrets where name='rigmarket_payment_job_url';
  if secret_id is null then perform vault.create_secret(p_url,'rigmarket_payment_job_url');
  else perform vault.update_secret(secret_id,p_url); end if;
  select jobid into old_job from cron.job where jobname='rigmarket-payment-reconcile';
  if old_job is not null then perform cron.unschedule(old_job); end if;
  perform cron.schedule('rigmarket-payment-reconcile','*/2 * * * *',$job$
    select net.http_post(
      url:=(select decrypted_secret from vault.decrypted_secrets where name='rigmarket_payment_job_url'),
      headers:=jsonb_build_object('Content-Type','application/json','x-job-secret',
        (select decrypted_secret from vault.decrypted_secrets where name='rigmarket_payment_job_secret')),
      body:='{}'::jsonb,timeout_milliseconds:=120000);
  $job$);
end; $$;
revoke all on function public.payment_schedule(text,text) from public,anon,authenticated;
grant execute on function public.payment_schedule(text,text) to service_role;
commit;
