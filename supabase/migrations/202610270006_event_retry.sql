begin;
alter table public.payment_events add column next_attempt_at timestamptz not null default now();
create index payment_events_retry on public.payment_events(next_attempt_at,created_at) where processed_at is null;
commit;
