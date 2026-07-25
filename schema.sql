-- ============================================================
-- Al Ihsan Dairies — Supabase schema
-- Run this once in Supabase Dashboard → SQL Editor → New query
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- PRODUCTS
-- ------------------------------------------------------------
create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  description text,
  urdu_description text,
  price numeric not null check (price >= 0),
  unit text not null default 'KG',
  stock numeric not null default 0 check (stock >= 0),
  low_stock_threshold numeric not null default 5,
  image_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- ORDERS
-- ------------------------------------------------------------
create sequence if not exists order_seq start 1000;

create or replace function generate_order_number()
returns text language sql as $$
  select 'ORD-' || nextval('order_seq');
$$;

create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  order_number text unique not null default generate_order_number(),
  customer_name text not null,
  contact text not null,
  address text not null,
  location_text text,
  lat double precision,
  lng double precision,
  product_id uuid references products(id),
  product_name text not null,
  qty numeric not null check (qty > 0),
  unit_price numeric not null,
  total numeric not null,
  payment_method text not null,
  status text not null default 'packing'
    check (status in ('packing','handed over to delivery service','out for delivery','delivered','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists orders_created_at_idx on orders (created_at desc);
create index if not exists orders_status_idx on orders (status);
create index if not exists orders_order_number_idx on orders (order_number);
create index if not exists orders_contact_idx on orders (contact);

-- ------------------------------------------------------------
-- updated_at triggers
-- ------------------------------------------------------------
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists products_updated_at on products;
create trigger products_updated_at before update on products
  for each row execute function set_updated_at();

drop trigger if exists orders_updated_at on orders;
create trigger orders_updated_at before update on orders
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- place_order: atomic stock check + decrement + order insert
-- Called by the public site using the anon key.
-- ------------------------------------------------------------
create or replace function place_order(
  p_customer_name text,
  p_contact text,
  p_address text,
  p_location_text text,
  p_lat double precision,
  p_lng double precision,
  p_product_slug text,
  p_qty numeric,
  p_payment_method text
) returns table(order_number text, total numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product products%rowtype;
  v_order orders%rowtype;
begin
  if p_qty <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  select * into v_product from products
    where slug = p_product_slug and active = true
    for update;

  if not found then
    raise exception 'Product not available';
  end if;

  if v_product.stock < p_qty then
    raise exception 'Only % % left in stock', v_product.stock, v_product.unit;
  end if;

  update products set stock = stock - p_qty where id = v_product.id;

  insert into orders (
    customer_name, contact, address, location_text, lat, lng,
    product_id, product_name, qty, unit_price, total, payment_method
  ) values (
    p_customer_name, p_contact, p_address, p_location_text, p_lat, p_lng,
    v_product.id, v_product.name, p_qty, v_product.price, v_product.price * p_qty, p_payment_method
  ) returning * into v_order;

  return query select v_order.order_number, v_order.total;
end;
$$;

-- ------------------------------------------------------------
-- get_order_status: public lookup, limited columns, requires
-- both order number AND contact number to match (basic guard
-- against strangers browsing other people's orders).
-- ------------------------------------------------------------
create or replace function get_order_status(p_order_number text, p_contact text)
returns table(
  order_number text, status text, product_name text, qty numeric,
  total numeric, payment_method text, created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select order_number, status, product_name, qty, total, payment_method, created_at
  from orders
  where order_number = p_order_number
    and regexp_replace(contact, '\D', '', 'g') = regexp_replace(p_contact, '\D', '', 'g');
$$;

-- ------------------------------------------------------------
-- Row Level Security
-- ------------------------------------------------------------
alter table products enable row level security;
alter table orders enable row level security;

drop policy if exists "Public can view active products" on products;
create policy "Public can view active products" on products
  for select using (active = true);

drop policy if exists "Admins can manage products" on products;
create policy "Admins can manage products" on products
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- No direct public select/insert policy on orders: inserts go through
-- place_order() (security definer) and lookups go through
-- get_order_status() (security definer, column-limited). This keeps
-- other customers' names/addresses/phone numbers private.
drop policy if exists "Admins can view orders" on orders;
create policy "Admins can view orders" on orders
  for select using (auth.role() = 'authenticated');

drop policy if exists "Admins can update orders" on orders;
create policy "Admins can update orders" on orders
  for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- Let the anon (public) role call the two RPCs above.
grant execute on function place_order(text,text,text,text,double precision,double precision,text,numeric,text) to anon;
grant execute on function get_order_status(text,text) to anon;

-- ------------------------------------------------------------
-- Seed the one current product (Pure Desi Ghee).
-- Adjust stock to your real current stock in KG.
-- ------------------------------------------------------------
insert into products (name, slug, description, urdu_description, price, unit, stock, image_url)
values (
  'Pure Desi Ghee',
  'pure-desi-ghee',
  'Sourced from free-grazing cows, our Desi Ghee is hand-churned using age-old methods.',
  'آزاد چرنے والی گائے کے دودھ سے تیار — ہمارا دیسی گھی ہاتھ سے مکھن نکال کر بنایا جاتا ہے۔',
  3500,
  'KG',
  100,
  'assets/ghee-hero.jpg'
)
on conflict (slug) do nothing;

-- ------------------------------------------------------------
-- Realtime: allow the admin panel to subscribe to live order changes
-- ------------------------------------------------------------
alter publication supabase_realtime add table orders;
