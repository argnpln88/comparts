-- Stage 1 only: identity and public catalog. No client order/payment writes.
begin;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 100),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.seller_profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  shop_name text not null check (char_length(shop_name) between 2 and 100),
  description text not null default '',
  logo_url text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
  -- Private contact and dispatch address fields belong in a separate table later.
);

create table public.categories (
  id text primary key,
  name text not null unique
);
insert into public.categories(id, name) values
  ('cpu', 'CPUs'), ('motherboard', 'Motherboards'), ('gpu', 'Graphics cards'),
  ('ram', 'RAM'), ('storage', 'SSDs & HDDs'), ('psu', 'Power supplies'),
  ('casePart', 'Cases'), ('cooler', 'Coolers & fans'), ('monitor', 'Monitors'),
  ('peripherals', 'Peripherals');

create table public.products (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.seller_profiles(id) on delete restrict,
  category_id text not null references public.categories(id),
  name text not null check (char_length(name) between 2 and 200),
  brand text not null,
  description text not null default '',
  price_centavos bigint not null check (price_centavos > 0 and price_centavos <= 10000000000),
  condition text not null check (condition in ('new', 'used', 'refurbished')),
  stock integer not null default 0 check (stock >= 0),
  specifications jsonb not null default '{}'::jsonb check (jsonb_typeof(specifications) = 'object'),
  warranty text not null default '',
  image_url text check (image_url is null or image_url like 'https://%'),
  status text not null default 'draft' check (status in ('draft', 'published', 'paused', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index products_catalog_created on public.products(status, created_at desc, id);
create index products_catalog_category_price on public.products(category_id, price_centavos, id) where status = 'published';
create index products_seller_id on public.products(seller_id);

create function public.foundation_touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
create trigger profiles_updated before update on public.profiles for each row execute function public.foundation_touch_updated_at();
create trigger sellers_updated before update on public.seller_profiles for each row execute function public.foundation_touch_updated_at();
create trigger products_updated before update on public.products for each row execute function public.foundation_touch_updated_at();

create function public.foundation_create_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name)
    values (new.id, left(coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''), 'Builder'), 100));
  return new;
end;
$$;
revoke all on function public.foundation_create_profile() from public, anon, authenticated;
create trigger rigmarket_user_created after insert on auth.users for each row execute function public.foundation_create_profile();

alter table public.profiles enable row level security;
alter table public.seller_profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;

revoke all on table public.profiles, public.seller_profiles, public.categories, public.products from anon, authenticated;
grant select on public.profiles to authenticated;
grant update(display_name, avatar_url) on public.profiles to authenticated;
grant select on public.seller_profiles, public.categories, public.products to anon, authenticated;
grant all on public.profiles, public.seller_profiles, public.categories, public.products to service_role;

create policy profiles_read_own on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy public_categories on public.categories for select to anon, authenticated using (true);
create policy public_approved_shops on public.seller_profiles for select to anon, authenticated
  using (status = 'approved');
create policy own_seller_profile on public.seller_profiles for select to authenticated
  using (id = (select auth.uid()));
create policy public_published_products on public.products for select to anon, authenticated
  using (status = 'published' and exists (
    select 1 from public.seller_profiles s where s.id = seller_id and s.status = 'approved'
  ));

-- Backfill Auth users that predate this migration without granting any role.
insert into public.profiles(id, display_name)
select id, left(coalesce(nullif(btrim(raw_user_meta_data ->> 'display_name'), ''), 'Builder'), 100)
from auth.users on conflict(id) do nothing;

commit;
