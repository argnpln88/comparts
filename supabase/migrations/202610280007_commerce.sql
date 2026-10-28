begin;

alter table public.orders drop constraint orders_status_check;
alter table public.orders add constraint orders_status_check check (status in
  ('creating','creation_unknown','payment_pending','paid','expired','cancelled','failed','payment_review','refund_pending','refunded','refund_failed','cod_pending'));
alter table public.orders drop constraint orders_fulfillment_check;
alter table public.orders add constraint orders_fulfillment_check check (fulfillment in ('pickup_demo','delivery'));
alter table public.orders
  add column payment_method text not null default 'xendit' check (payment_method in ('xendit','cod')),
  add column fulfillment_status text not null default 'processing' check (fulfillment_status in ('processing','shipped','delivered','cancelled')),
  add column shipping_address jsonb check (jsonb_typeof(shipping_address)='object'),
  add column courier text,
  add column tracking_number text,
  add column shipped_at timestamptz,
  add column delivered_at timestamptz;
update public.orders set fulfillment_status='cancelled' where status in ('cancelled','expired','failed');
create index orders_seller_date on public.orders(seller_id,created_at desc);
create policy seller_orders on public.orders for select to authenticated using (seller_id=(select auth.uid()));

create table public.order_delivery_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  actor_id uuid not null references auth.users(id),
  event text not null check (event in ('placed','shipped','received','cancelled')),
  note text not null default '',
  created_at timestamptz not null default now()
);
create index delivery_events_order on public.order_delivery_events(order_id,created_at);
alter table public.order_delivery_events enable row level security;
revoke all on public.order_delivery_events from public,anon,authenticated;
grant select on public.order_delivery_events to authenticated;
grant all on public.order_delivery_events to service_role;
create policy participants_delivery_events on public.order_delivery_events for select to authenticated using (
  exists(select 1 from public.orders o where o.id=order_id and (o.buyer_id=(select auth.uid()) or o.seller_id=(select auth.uid())))
);

create table public.order_reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id),
  product_id uuid not null references public.products(id),
  buyer_id uuid not null references auth.users(id),
  reviewer_name text not null check (char_length(reviewer_name) between 1 and 100),
  rating integer not null check (rating between 1 and 5),
  review_notes text not null check (char_length(review_notes) between 5 and 2000),
  created_at timestamptz not null default now()
);
create index order_reviews_product on public.order_reviews(product_id,created_at desc);
alter table public.order_reviews enable row level security;
revoke all on public.order_reviews from public,anon,authenticated;
grant all on public.order_reviews to service_role;
-- Public reviews are exposed only through the projection below, without buyer/order IDs.

create function public.commerce_shipping(p_shipping jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare n text; ph text; a text; c text; z text;
begin
  if p_shipping is null or jsonb_typeof(p_shipping)<>'object' then raise exception 'Shipping address is required'; end if;
  n:=btrim(coalesce(p_shipping->>'recipient',''));
  ph:=btrim(coalesce(p_shipping->>'phone',''));
  a:=btrim(coalesce(p_shipping->>'address',''));
  c:=btrim(coalesce(p_shipping->>'city',''));
  z:=btrim(coalesce(p_shipping->>'postal_code',''));
  if char_length(n) not between 2 and 100 then raise exception 'Shipping recipient must be 2 to 100 characters'; end if;
  if ph !~ '^\+?[0-9][0-9 -]{8,18}$' then raise exception 'Shipping phone number is invalid'; end if;
  if char_length(a) not between 8 and 400 then raise exception 'Shipping street address must be 8 to 400 characters'; end if;
  if char_length(c) not between 2 and 100 then raise exception 'Shipping city is required'; end if;
  if z !~ '^[0-9]{4}$' then raise exception 'Shipping postal code must contain four digits'; end if;
  return jsonb_build_object('recipient',n,'phone',ph,'address',a,'city',c,'postal_code',z);
end; $$;

create function public.commerce_create_cod(p_actor uuid,p_product uuid,p_quantity integer,p_key uuid,p_expected_unit bigint,p_shipping jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.orders; q jsonb; address jsonb;
begin
  if p_actor is null or p_key is null then raise exception 'Order account and checkout key are required'; end if;
  address:=public.commerce_shipping(p_shipping);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text,0));
  select * into o from public.orders where buyer_id=p_actor and idempotency_key=p_key;
  if o.id is not null then
    if o.payment_method<>'cod' or o.product_id is distinct from p_product or o.quantity is distinct from p_quantity
      or o.unit_price_centavos is distinct from p_expected_unit or o.shipping_address is distinct from address
      then raise exception 'Checkout key was already used for a different purchase'; end if;
    return to_jsonb(o);
  end if;
  if exists(select 1 from public.orders where buyer_id=p_actor and product_id=p_product and status in ('creating','creation_unknown','payment_pending','payment_review'))
    then raise exception 'Finish or cancel an existing checkout first'; end if;
  select * into o from public.orders where buyer_id=p_actor and product_id=p_product and status='cod_pending' and fulfillment_status='processing' order by created_at desc limit 1;
  if o.id is not null then
    if o.quantity is distinct from p_quantity or o.unit_price_centavos is distinct from p_expected_unit or o.shipping_address is distinct from address
      then raise exception 'Cash on delivery order already open for this item. Complete or cancel it first'; end if;
    return to_jsonb(o);
  end if;
  if (select count(*) from public.orders where buyer_id=p_actor and status='cod_pending')>=5
    then raise exception 'Cash on delivery limit reached. Complete or cancel an open order first'; end if;
  perform 1 from public.products where id=p_product for update;
  q:=public.payment_quote(p_actor,p_product,p_quantity);
  if (q->>'unit_price_centavos')::bigint is distinct from p_expected_unit then raise exception 'Price changed. Review the new total before ordering'; end if;
  insert into public.orders(buyer_id,seller_id,product_id,product_name,quantity,unit_price_centavos,total_centavos,idempotency_key,payment_method,status,fulfillment,shipping_address)
    select p_actor,seller_id,id,name,p_quantity,price_centavos,price_centavos*p_quantity,p_key,'cod','cod_pending','delivery',address
    from public.products where id=p_product returning * into o;
  update public.products set stock=stock-p_quantity where id=p_product;
  delete from public.cart_items where buyer_id=p_actor and product_id=p_product;
  insert into public.order_delivery_events(order_id,actor_id,event,note) values(o.id,p_actor,'placed','Cash on delivery order placed');
  return to_jsonb(o);
end; $$;

create function public.commerce_reserve_online(p_actor uuid,p_product uuid,p_quantity integer,p_key uuid,p_expected_unit bigint,p_shipping jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb; o public.orders; address jsonb;
begin
  address:=public.commerce_shipping(p_shipping);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text,0));
  if exists(select 1 from public.orders where buyer_id=p_actor and product_id=p_product and status='cod_pending' and fulfillment_status='processing')
    then raise exception 'Finish or cancel an existing checkout first'; end if;
  r:=public.payment_reserve(p_actor,p_product,p_quantity,p_key,p_expected_unit);
  select * into strict o from public.orders where id=(r->'order'->>'id')::uuid for update;
  if o.payment_method<>'xendit' then raise exception 'Checkout key was already used for a different purchase'; end if;
  if not (r->>'create')::boolean then
    if o.shipping_address is distinct from address then raise exception 'Finish or cancel an existing checkout before changing its shipping address'; end if;
    return r;
  end if;
  update public.orders set fulfillment='delivery',shipping_address=address where id=o.id returning * into o;
  insert into public.order_delivery_events(order_id,actor_id,event,note) values(o.id,p_actor,'placed','Online checkout started');
  return jsonb_build_object('order',to_jsonb(o),'create',true);
end; $$;

create function public.commerce_dispatch(p_actor uuid,p_order uuid,p_courier text,p_tracking text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.orders;
begin
  select * into o from public.orders where id=p_order for update;
  if o.id is null or o.seller_id is distinct from p_actor then raise exception 'Only the seller can dispatch this order'; end if;
  if o.fulfillment_status in ('shipped','delivered') then return to_jsonb(o); end if;
  if o.fulfillment<>'delivery' or o.shipping_address is null or o.fulfillment_status<>'processing' or o.status not in ('paid','cod_pending')
    then raise exception 'Order is not ready for delivery'; end if;
  if char_length(btrim(coalesce(p_courier,''))) not between 2 and 100 then raise exception 'Delivery courier is required'; end if;
  if char_length(btrim(coalesce(p_tracking,''))) not between 3 and 100 then raise exception 'Delivery tracking number is required'; end if;
  update public.orders set fulfillment_status='shipped',courier=btrim(p_courier),tracking_number=btrim(p_tracking),shipped_at=now()
    where id=p_order returning * into o;
  insert into public.order_delivery_events(order_id,actor_id,event,note) values(o.id,p_actor,'shipped',o.courier||' · '||o.tracking_number);
  return to_jsonb(o);
end; $$;

create function public.commerce_receive(p_actor uuid,p_order uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.orders;
begin
  select * into o from public.orders where id=p_order for update;
  if o.id is null or o.buyer_id is distinct from p_actor then raise exception 'Only the buyer can confirm receipt'; end if;
  if o.fulfillment_status='delivered' then return to_jsonb(o); end if;
  if o.fulfillment_status<>'shipped' or o.status not in ('paid','cod_pending') then raise exception 'Order is not out for delivery'; end if;
  update public.orders set fulfillment_status='delivered',delivered_at=now(),
    status=case when payment_method='cod' then 'paid' else status end,
    paid_at=case when payment_method='cod' then coalesce(paid_at,now()) else paid_at end
    where id=p_order returning * into o;
  insert into public.order_delivery_events(order_id,actor_id,event,note) values(o.id,p_actor,'received',
    case when o.payment_method='cod' then 'Buyer confirmed receipt and cash payment' else 'Buyer confirmed receipt' end);
  return to_jsonb(o);
end; $$;

create function public.commerce_cancel_cod(p_actor uuid,p_order uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.orders;
begin
  select * into o from public.orders where id=p_order for update;
  if o.id is null or (o.buyer_id is distinct from p_actor and o.seller_id is distinct from p_actor) then raise exception 'Only the buyer or seller can cancel this order'; end if;
  if o.payment_method<>'cod' then raise exception 'Cash on delivery order required'; end if;
  if o.status='cancelled' then return to_jsonb(o); end if;
  if o.status<>'cod_pending' or o.fulfillment_status<>'processing' then raise exception 'Order can only be cancelled before dispatch'; end if;
  if o.stock_reserved then update public.products set stock=stock+o.quantity where id=o.product_id; end if;
  update public.orders set status='cancelled',fulfillment_status='cancelled',stock_reserved=false where id=p_order returning * into o;
  insert into public.order_delivery_events(order_id,actor_id,event,note) values(o.id,p_actor,'cancelled','Order cancelled before dispatch');
  return to_jsonb(o);
end; $$;

create function public.commerce_review(p_actor uuid,p_order uuid,p_rating integer,p_notes text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.orders; r public.order_reviews; n text;
begin
  select * into o from public.orders where id=p_order for update;
  if o.id is null or o.buyer_id is distinct from p_actor then raise exception 'Only the buyer can review this order'; end if;
  if o.fulfillment_status<>'delivered' or o.status<>'paid' then raise exception 'Only delivered purchases can be reviewed'; end if;
  if p_rating is null or p_rating not between 1 and 5 then raise exception 'Rating must be between 1 and 5'; end if;
  if char_length(btrim(coalesce(p_notes,''))) not between 5 and 2000 then raise exception 'Review notes must be 5 to 2000 characters'; end if;
  select * into r from public.order_reviews where order_id=p_order;
  if r.id is not null then
    if r.rating is distinct from p_rating or r.review_notes is distinct from btrim(p_notes) then raise exception 'Review already submitted for this purchase'; end if;
    return to_jsonb(r);
  end if;
  select display_name into n from public.profiles where id=p_actor;
  insert into public.order_reviews(order_id,product_id,buyer_id,reviewer_name,rating,review_notes)
    values(o.id,o.product_id,p_actor,coalesce(n,'Buyer'),p_rating,btrim(p_notes)) returning * into r;
  return to_jsonb(r);
end; $$;

create function public.product_review_summary(p_product uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('count',count(*),'average',coalesce(round(avg(r.rating),1),0),'reviews',
    coalesce((select jsonb_agg(to_jsonb(s)) from (
      select reviewer_name,rating,review_notes,created_at from public.order_reviews where product_id=p_product
      and exists(select 1 from public.products p join public.seller_profiles sp on sp.id=p.seller_id where p.id=p_product and p.status='published' and sp.status='approved')
      order by created_at desc limit 20
    ) s),'[]'::jsonb))
  from public.order_reviews r where r.product_id=p_product
  and exists(select 1 from public.products p join public.seller_profiles sp on sp.id=p.seller_id where p.id=p_product and p.status='published' and sp.status='approved');
$$;

revoke all on function public.commerce_shipping(jsonb),public.commerce_create_cod(uuid,uuid,integer,uuid,bigint,jsonb),
  public.commerce_reserve_online(uuid,uuid,integer,uuid,bigint,jsonb),public.commerce_dispatch(uuid,uuid,text,text),
  public.commerce_receive(uuid,uuid),public.commerce_cancel_cod(uuid,uuid),public.commerce_review(uuid,uuid,integer,text)
  from public,anon,authenticated;
grant execute on function public.commerce_shipping(jsonb),public.commerce_create_cod(uuid,uuid,integer,uuid,bigint,jsonb),
  public.commerce_reserve_online(uuid,uuid,integer,uuid,bigint,jsonb),public.commerce_dispatch(uuid,uuid,text,text),
  public.commerce_receive(uuid,uuid),public.commerce_cancel_cod(uuid,uuid),public.commerce_review(uuid,uuid,integer,text)
  to service_role;
revoke all on function public.product_review_summary(uuid) from public;
grant execute on function public.product_review_summary(uuid) to anon,authenticated,service_role;
commit;
