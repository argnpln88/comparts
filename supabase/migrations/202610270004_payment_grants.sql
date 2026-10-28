-- Supabase projects can have default table grants. Remove them explicitly:
-- TRUNCATE bypasses RLS and must never be available to mobile clients.
begin;
revoke all on public.orders,public.cart_items,public.payment_events,public.payment_attempts,public.refunds,public.payment_admins from public,anon,authenticated;
grant select on public.orders to authenticated;
grant select,insert,update,delete on public.cart_items to authenticated;
grant all on public.orders,public.cart_items,public.payment_events,public.payment_attempts,public.refunds,public.payment_admins to service_role;
commit;
