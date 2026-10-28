-- Xendit TEST MODE only. Buy Now/pickup demonstration; no real seller settlement.
begin;

create table public.cart_items (
  buyer_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity integer not null check (quantity between 1 and 20),
  primary key (buyer_id, product_id)
);
alter table public.cart_items enable row level security;
grant select, insert, update, delete on public.cart_items to authenticated;
grant all on public.cart_items to service_role;
create policy own_cart on public.cart_items to authenticated
  using (buyer_id = (select auth.uid())) with check (buyer_id = (select auth.uid()));

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete restrict,
  seller_id uuid not null references public.seller_profiles(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  product_name text not null,
  quantity integer not null check (quantity between 1 and 20),
  unit_price_centavos bigint not null check (unit_price_centavos > 0),
  total_centavos bigint not null check (total_centavos > 0 and total_centavos <= 10000000000),
  currency text not null default 'PHP' check (currency = 'PHP'),
  environment text not null default 'test' check (environment = 'test'),
  fulfillment text not null default 'pickup_demo' check (fulfillment = 'pickup_demo'),
  status text not null default 'creating' check (status in
    ('creating','creation_unknown','payment_pending','paid','expired','cancelled','failed','payment_review','refund_pending','refunded','refund_failed')),
  idempotency_key uuid not null,
  creation_token uuid not null default gen_random_uuid(),
  payment_session_id text unique,
  payment_request_id text,
  payment_id text,
  payment_link_url text,
  expires_at timestamptz,
  stock_reserved boolean not null default true,
  paid_at timestamptz,
  last_checked_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (buyer_id, idempotency_key),
  check (total_centavos = unit_price_centavos * quantity)
);
create index orders_buyer_date on public.orders(buyer_id, created_at desc);
create index orders_reconcile on public.orders(last_checked_at nulls first) where status in ('creating','creation_unknown','payment_pending','refund_pending','refund_failed');
create trigger orders_updated before update on public.orders for each row execute function public.foundation_touch_updated_at();
alter table public.orders enable row level security;
grant select on public.orders to authenticated;
grant all on public.orders to service_role;
create policy own_orders on public.orders for select to authenticated using (buyer_id = (select auth.uid()));

create table public.payment_events (
  id uuid primary key default gen_random_uuid(),
  dedupe_key text not null unique,
  event_type text not null,
  payload jsonb not null,
  session_id text,
  processed_at timestamptz,
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now()
);
create index payment_events_pending on public.payment_events(created_at) where processed_at is null;
create table public.payment_attempts (
  payment_request_id text primary key,
  order_id uuid not null references public.orders(id),
  status text not null default 'UNKNOWN',
  updated_at timestamptz not null default now()
);
create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id),
  provider_id text unique,
  status text not null default 'creating' check (status in ('creating','unknown','pending','succeeded','failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.payment_admins (user_id uuid primary key references auth.users(id));
alter table public.payment_events enable row level security;
alter table public.payment_attempts enable row level security;
alter table public.refunds enable row level security;
alter table public.payment_admins enable row level security;
revoke all on public.payment_events, public.payment_attempts, public.refunds, public.payment_admins from anon, authenticated;
grant all on public.payment_events, public.payment_attempts, public.refunds, public.payment_admins to service_role;

create function public.payment_quote(p_buyer uuid, p_product uuid, p_quantity integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.products; s public.seller_profiles;
begin
  if p_quantity is null or p_quantity not between 1 and 20 then raise exception 'Quantity must be between 1 and 20'; end if;
  select * into p from public.products where id=p_product;
  select * into s from public.seller_profiles where id=p.seller_id;
  if p.id is null or p.status <> 'published' or s.status <> 'approved' then raise exception 'Listing unavailable'; end if;
  if p.seller_id=p_buyer then raise exception 'You cannot buy your own listing'; end if;
  if p.stock<p_quantity then raise exception 'Insufficient stock'; end if;
  if p.price_centavos*p_quantity>10000000000 then raise exception 'Order total is too large'; end if;
  return jsonb_build_object('product_id',p.id,'product_name',p.name,'quantity',p_quantity,
    'unit_price_centavos',p.price_centavos,'total_centavos',p.price_centavos*p_quantity,
    'currency','PHP','environment','test','fulfillment','pickup_demo');
end; $$;

create function public.payment_reserve(p_buyer uuid, p_product uuid, p_quantity integer, p_key uuid, p_expected_unit bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.orders; q jsonb;
begin
  -- Serialize by buyer/product, including callers using different idempotency keys.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_buyer::text,0));
  select * into o from public.orders where buyer_id=p_buyer and idempotency_key=p_key;
  if o.id is not null then
    if o.product_id<>p_product or o.quantity<>p_quantity then raise exception 'Checkout key was already used for a different purchase'; end if;
    return jsonb_build_object('order',to_jsonb(o),'create',false);
  end if;
  select * into o from public.orders where buyer_id=p_buyer and product_id=p_product
    and status in ('creating','creation_unknown','payment_pending','payment_review') order by created_at desc limit 1;
  if o.id is not null then return jsonb_build_object('order',to_jsonb(o),'create',false); end if;
  if (select count(*) from public.orders where buyer_id=p_buyer and status in ('creating','creation_unknown','payment_pending','payment_review'))>=5
    then raise exception 'Finish or cancel an existing checkout first'; end if;
  perform 1 from public.products where id=p_product for update;
  q:=public.payment_quote(p_buyer,p_product,p_quantity);
  if (q->>'unit_price_centavos')::bigint is distinct from p_expected_unit then raise exception 'Price changed. Review the new total before paying'; end if;
  insert into public.orders(buyer_id,seller_id,product_id,product_name,quantity,unit_price_centavos,total_centavos,idempotency_key)
    select p_buyer,seller_id,id,name,p_quantity,price_centavos,price_centavos*p_quantity,p_key from public.products where id=p_product returning * into o;
  update public.products set stock=stock-p_quantity where id=p_product;
  delete from public.cart_items where buyer_id=p_buyer and product_id=p_product;
  return jsonb_build_object('order',to_jsonb(o),'create',true);
end; $$;

create function public.payment_attach(p_order uuid, p_session text, p_url text, p_expires timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare o public.orders;
begin
  select * into strict o from public.orders where id=p_order for update;
  if o.payment_session_id is not null and o.payment_session_id<>p_session then raise exception 'Conflicting payment session'; end if;
  if o.status not in ('creating','creation_unknown','payment_pending') then return; end if;
  update public.orders set payment_session_id=p_session,payment_link_url=p_url,expires_at=p_expires,
    status='payment_pending',last_error=null where id=p_order;
end; $$;

create function public.payment_apply(p_order uuid, p_state text, p_request text default null, p_payment text default null, p_error text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare o public.orders;
begin
  select * into strict o from public.orders where id=p_order for update;
  if p_state not in ('paid','expired','cancelled','failed','creation_unknown','payment_review','payment_pending') then raise exception 'Unsupported payment transition'; end if;
  if o.status in ('paid','refund_pending','refunded','refund_failed') then return; end if;
  if p_state='paid' and not o.stock_reserved then
    update public.orders set status='payment_review',last_error='Late payment after reservation release; refund review required',payment_request_id=p_request,payment_id=p_payment where id=p_order;
    return;
  end if;
  if o.status in ('expired','cancelled','failed') and p_state<>'paid' then return; end if;
  if p_state in ('expired','cancelled','failed') and o.stock_reserved then
    update public.products set stock=stock+o.quantity where id=o.product_id;
  end if;
  update public.orders set status=p_state,
    stock_reserved=case when p_state in ('expired','cancelled','failed') then false else stock_reserved end,
    payment_request_id=coalesce(p_request,payment_request_id),payment_id=coalesce(p_payment,payment_id),
    paid_at=case when p_state='paid' then now() else paid_at end,last_checked_at=now(),last_error=p_error where id=p_order;
end; $$;

create function public.payment_refund_begin(p_order uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare o public.orders; r public.refunds;
begin
  select * into strict o from public.orders where id=p_order for update;
  select * into r from public.refunds where order_id=p_order;
  if r.id is not null then return jsonb_build_object('refund',to_jsonb(r),'create',false); end if;
  if o.status<>'paid' or o.payment_request_id is null then raise exception 'Only confirmed paid orders can be refunded'; end if;
  insert into public.refunds(order_id) values(p_order) returning * into r;
  update public.orders set status='refund_pending' where id=p_order;
  return jsonb_build_object('refund',to_jsonb(r),'create',true);
end; $$;

create function public.payment_refund_apply(p_refund uuid,p_status text,p_provider text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.refunds; o public.orders;
begin
  if p_status not in ('unknown','pending','succeeded','failed') then raise exception 'Invalid refund state'; end if;
  select * into strict r from public.refunds where id=p_refund for update;
  if r.status='succeeded' then return; end if;
  select * into strict o from public.orders where id=r.order_id for update;
  update public.refunds set status=p_status,provider_id=coalesce(p_provider,provider_id),updated_at=now() where id=p_refund;
  update public.orders set status=case when p_status='succeeded' then 'refunded' when p_status='failed' then 'refund_failed' else 'refund_pending' end where id=r.order_id;
  -- No automatic restock on refund: physical return/pickup status needs review.
end; $$;

revoke all on function public.payment_quote(uuid,uuid,integer), public.payment_reserve(uuid,uuid,integer,uuid,bigint),
  public.payment_attach(uuid,text,text,timestamptz), public.payment_apply(uuid,text,text,text,text),
  public.payment_refund_begin(uuid),public.payment_refund_apply(uuid,text,text) from public, anon, authenticated;
grant execute on function public.payment_quote(uuid,uuid,integer), public.payment_reserve(uuid,uuid,integer,uuid,bigint),
  public.payment_attach(uuid,text,text,timestamptz), public.payment_apply(uuid,text,text,text,text),
  public.payment_refund_begin(uuid),public.payment_refund_apply(uuid,text,text) to service_role;
commit;
