-- Transactional tests: all artificial paid/refund states are rolled back.
begin;
do $$
declare buyer uuid; seller uuid; outsider uuid; product uuid; result jsonb; replay jsonb; key uuid:=gen_random_uuid(); oid uuid; rid uuid; failed boolean;
begin
  select id into strict buyer from auth.users where email='rigmarket-demo-buyer@example.com';
  select id into strict seller from auth.users where email='rigmarket-demo-seller@example.com';
  select id into strict outsider from auth.users where email='rigmarket-demo-outsider@example.com';
  insert into public.products(seller_id,category_id,name,brand,price_centavos,condition,stock,status)
    values(seller,'peripherals','Rollback payment test','TEST',10050,'new',1,'published') returning id into product;
  result:=public.payment_reserve(buyer,product,1,key,10050);
  oid:=(result->'order'->>'id')::uuid;
  if not (result->>'create')::boolean or (select stock from public.products where id=product)<>0 then raise exception 'Reservation failed'; end if;
  replay:=public.payment_reserve(buyer,product,1,key,10050);
  if (replay->>'create')::boolean or replay->'order'->>'id'<>oid::text then raise exception 'Idempotency failed'; end if;
  replay:=public.payment_reserve(buyer,product,1,gen_random_uuid(),10050);
  if replay->'order'->>'id'<>oid::text then raise exception 'Unresolved order reused incorrectly'; end if;
  failed:=false;
  begin perform public.payment_reserve(outsider,product,1,gen_random_uuid(),10050); exception when others then failed:=true; end;
  if not failed then raise exception 'Oversold final unit'; end if;
  perform public.payment_apply(oid,'failed');
  perform public.payment_apply(oid,'failed');
  if (select stock from public.products where id=product)<>1 then raise exception 'Stock restored more than once'; end if;
  failed:=false;
  begin perform public.payment_quote(seller,product,1); exception when others then failed:=true; end;
  if not failed then raise exception 'Self purchase allowed'; end if;
  failed:=false;
  begin perform public.payment_reserve(buyer,product,1,gen_random_uuid(),1); exception when others then failed:=true; end;
  if not failed then raise exception 'Changed price accepted'; end if;
  result:=public.payment_reserve(buyer,product,1,gen_random_uuid(),10050); oid:=(result->'order'->>'id')::uuid;
  perform public.payment_attach(oid,'ps-rollback-test','https://xen.to/rollback',now()+interval '30 minutes');
  perform public.payment_apply(oid,'paid','pr-rollback','py-rollback');
  perform public.payment_apply(oid,'expired');
  if (select status from public.orders where id=oid)<>'paid' or (select stock from public.products where id=product)<>0 then raise exception 'Paid order regressed'; end if;
  result:=public.payment_refund_begin(oid); rid:=(result->'refund'->>'id')::uuid;
  replay:=public.payment_refund_begin(oid);
  if (replay->>'create')::boolean or replay->'refund'->>'id'<>rid::text then raise exception 'Duplicate refund allowed'; end if;
  perform public.payment_refund_apply(rid,'succeeded','rfd-rollback');
  perform public.payment_refund_apply(rid,'failed');
  if (select status from public.orders where id=oid)<>'refunded' then raise exception 'Final refund regressed'; end if;
  if has_function_privilege('authenticated','public.payment_apply(uuid,text,text,text,text)','execute') then raise exception 'Client can mark orders paid'; end if;
  if has_table_privilege('authenticated','public.orders','update') then raise exception 'Client can update orders'; end if;
  if has_table_privilege('authenticated','public.orders','truncate') or has_table_privilege('authenticated','public.cart_items','truncate') then raise exception 'Client can truncate marketplace tables'; end if;
  if has_table_privilege('anon','public.payment_events','select') then raise exception 'Public can read payment inbox'; end if;
  perform set_config('payment_test.order_id',oid::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
end $$;
set local role authenticated;
do $$ begin
  if exists(select 1 from public.orders where id=current_setting('payment_test.order_id')::uuid) then raise exception 'Cross-buyer order leaked'; end if;
end $$;
reset role;
rollback;
select 'Payment transaction, idempotency, inventory, refund, privilege and RLS tests passed' as result;
