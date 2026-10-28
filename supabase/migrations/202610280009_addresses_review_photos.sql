begin;

create table public.delivery_addresses (
  buyer_id uuid primary key references auth.users(id) on delete cascade,
  address jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.delivery_addresses enable row level security;
revoke all on public.delivery_addresses from public,anon,authenticated;
grant select on public.delivery_addresses to authenticated;
grant all on public.delivery_addresses to service_role;
create policy own_delivery_address on public.delivery_addresses for select to authenticated
  using (buyer_id=(select auth.uid()));

create function public.save_delivery_address(p_shipping jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a jsonb; actor uuid:=auth.uid();
begin
  if actor is null then raise exception 'Sign in to save your delivery address'; end if;
  a:=public.commerce_shipping(p_shipping);
  insert into public.delivery_addresses(buyer_id,address) values(actor,a)
    on conflict(buyer_id) do update set address=excluded.address,updated_at=now();
  return a;
end; $$;
revoke all on function public.save_delivery_address(jsonb) from public,anon;
grant execute on function public.save_delivery_address(jsonb) to authenticated;

alter table public.order_reviews add column photo_paths text[] not null default '{}'
  check(cardinality(photo_paths)<=3);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('review-photos','review-photos',true,3145728,array['image/jpeg','image/png','image/webp']);

-- Uploads belong to a completed purchase. Clients cannot replace/delete photos.
create function public.can_upload_review_photo(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.orders o where o.id::text=split_part(p_name,'/',1)
    and o.buyer_id=auth.uid() and o.status='paid' and o.fulfillment_status='delivered'
    and p_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'
    and not exists(select 1 from public.order_reviews r where r.order_id=o.id)
    and (select count(*) from storage.objects s where s.bucket_id='review-photos'
      and split_part(s.name,'/',1)=o.id::text)<9);
$$;
revoke all on function public.can_upload_review_photo(text) from public,anon;
grant execute on function public.can_upload_review_photo(text) to authenticated;
create policy completed_purchase_photo_upload on storage.objects for insert to authenticated
  with check(bucket_id='review-photos' and public.can_upload_review_photo(name));

create function public.commerce_review(p_actor uuid,p_order uuid,p_rating integer,p_notes text,p_photos text[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.orders; r public.order_reviews; n text; photo text; photos text[]:=coalesce(p_photos,'{}');
begin
  select * into o from public.orders where id=p_order for update;
  if o.id is null or o.buyer_id is distinct from p_actor then raise exception 'Only the buyer can review this order'; end if;
  if o.fulfillment_status<>'delivered' or o.status<>'paid' then raise exception 'Only delivered purchases can be reviewed'; end if;
  if p_rating is null or p_rating not between 1 and 5 then raise exception 'Rating must be between 1 and 5'; end if;
  if char_length(btrim(coalesce(p_notes,''))) not between 5 and 2000 then raise exception 'Review notes must be 5 to 2000 characters'; end if;
  if cardinality(photos)>3 then raise exception 'Review supports up to three item photos'; end if;
  foreach photo in array photos loop
    if photo is null or split_part(photo,'/',1)<>p_order::text or not exists(
      select 1 from storage.objects where bucket_id='review-photos' and name=photo
    ) then raise exception 'Review photo must be uploaded for this purchase'; end if;
  end loop;
  select * into r from public.order_reviews where order_id=p_order;
  if r.id is not null then
    if r.rating is distinct from p_rating or r.review_notes is distinct from btrim(p_notes)
      or r.photo_paths is distinct from photos then raise exception 'Review already submitted for this purchase'; end if;
    return to_jsonb(r);
  end if;
  select display_name into n from public.profiles where id=p_actor;
  insert into public.order_reviews(order_id,product_id,buyer_id,reviewer_name,rating,review_notes,photo_paths)
    values(o.id,o.product_id,p_actor,coalesce(n,'Buyer'),p_rating,btrim(p_notes),photos) returning * into r;
  return to_jsonb(r);
end; $$;
revoke all on function public.commerce_review(uuid,uuid,integer,text,text[]) from public,anon,authenticated;
grant execute on function public.commerce_review(uuid,uuid,integer,text,text[]) to service_role;

create or replace function public.commerce_review(p_actor uuid,p_order uuid,p_rating integer,p_notes text) returns jsonb
language sql security definer set search_path='' as $$
  select public.commerce_review(p_actor,p_order,p_rating,p_notes,'{}'::text[]);
$$;

create or replace function public.product_review_summary(p_product uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('count',count(*),'average',coalesce(round(avg(r.rating),1),0),'reviews',
    coalesce((select jsonb_agg(to_jsonb(s)) from (
      select reviewer_name,rating,review_notes,photo_paths,created_at from public.order_reviews where product_id=p_product
      and exists(select 1 from public.products p join public.seller_profiles sp on sp.id=p.seller_id where p.id=p_product and p.status='published' and sp.status='approved')
      order by created_at desc limit 20
    ) s),'[]'::jsonb))
  from public.order_reviews r where r.product_id=p_product
  and exists(select 1 from public.products p join public.seller_profiles sp on sp.id=p.seller_id where p.id=p_product and p.status='published' and sp.status='approved');
$$;
commit;
