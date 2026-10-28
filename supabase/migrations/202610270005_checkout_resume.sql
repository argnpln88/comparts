begin;
create or replace function public.payment_reserve(p_buyer uuid, p_product uuid, p_quantity integer, p_key uuid, p_expected_unit bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.orders; q jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_buyer::text,0));
  select * into o from public.orders where buyer_id=p_buyer and idempotency_key=p_key;
  if o.id is not null then
    if o.product_id<>p_product or o.quantity<>p_quantity then raise exception 'Checkout key was already used for a different purchase'; end if;
    return jsonb_build_object('order',to_jsonb(o),'create',false);
  end if;
  select * into o from public.orders where buyer_id=p_buyer and product_id=p_product
    and status in ('creating','creation_unknown','payment_pending','payment_review') order by created_at desc limit 1;
  if o.id is not null then
    if o.quantity is distinct from p_quantity or o.unit_price_centavos is distinct from p_expected_unit then
      raise exception 'Finish or cancel an existing checkout first';
    end if;
    return jsonb_build_object('order',to_jsonb(o),'create',false);
  end if;
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
commit;
