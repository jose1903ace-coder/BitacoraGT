-- Wedding Planner · Esquema de base de datos (Supabase)
-- Proyecto: pnlefnwngmktiykelkdd (aplicado como migraciones:
--   wedding_planner_schema, wp_lock_down_trigger_fn, wp_rename_hotel_to_venue)
-- Este archivo es una copia de referencia del esquema en producción.

create table if not exists public.wp_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('provider','client')),
  full_name text not null,
  phone text,
  created_at timestamptz not null default now()
);

create table if not exists public.wp_listings (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.wp_profiles(id) on delete cascade,
  category text not null check (category in ('venue','planner','florist','furniture')),
  title text not null,
  description text,
  location text,
  price_from numeric,
  price_unit text,
  image_url text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.wp_bookings (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.wp_listings(id) on delete cascade,
  client_id uuid not null references public.wp_profiles(id) on delete cascade,
  event_date date,
  guests int,
  message text,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now()
);

create index if not exists wp_listings_provider_idx on public.wp_listings(provider_id);
create index if not exists wp_listings_category_idx on public.wp_listings(category);
create index if not exists wp_bookings_listing_idx on public.wp_bookings(listing_id);
create index if not exists wp_bookings_client_idx on public.wp_bookings(client_id);

-- Crea el perfil automáticamente al registrarse, usando los metadatos del signup
create or replace function public.wp_handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.wp_profiles (id, role, full_name, phone)
  values (
    new.id,
    case when new.raw_user_meta_data->>'role' = 'provider' then 'provider' else 'client' end,
    coalesce(nullif(new.raw_user_meta_data->>'full_name',''), new.email),
    nullif(new.raw_user_meta_data->>'phone','')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke execute on function public.wp_handle_new_user() from public, anon, authenticated;

drop trigger if exists wp_on_auth_user_created on auth.users;
create trigger wp_on_auth_user_created
  after insert on auth.users
  for each row execute function public.wp_handle_new_user();

-- Seguridad a nivel de fila (RLS)
alter table public.wp_profiles enable row level security;
alter table public.wp_listings enable row level security;
alter table public.wp_bookings enable row level security;

create policy "wp_profiles_select" on public.wp_profiles for select using (true);
create policy "wp_profiles_insert_own" on public.wp_profiles for insert with check (auth.uid() = id);
create policy "wp_profiles_update_own" on public.wp_profiles for update using (auth.uid() = id);

create policy "wp_listings_select" on public.wp_listings for select using (true);
create policy "wp_listings_insert_own" on public.wp_listings for insert
  with check (
    auth.uid() = provider_id
    and exists (select 1 from public.wp_profiles p where p.id = auth.uid() and p.role = 'provider')
  );
create policy "wp_listings_update_own" on public.wp_listings for update using (auth.uid() = provider_id);
create policy "wp_listings_delete_own" on public.wp_listings for delete using (auth.uid() = provider_id);

create policy "wp_bookings_insert_client" on public.wp_bookings for insert
  with check (
    auth.uid() = client_id
    and exists (select 1 from public.wp_profiles p where p.id = auth.uid() and p.role = 'client')
  );
create policy "wp_bookings_select_own" on public.wp_bookings for select
  using (
    auth.uid() = client_id
    or exists (select 1 from public.wp_listings l where l.id = listing_id and l.provider_id = auth.uid())
  );
create policy "wp_bookings_update_parties" on public.wp_bookings for update
  using (
    auth.uid() = client_id
    or exists (select 1 from public.wp_listings l where l.id = listing_id and l.provider_id = auth.uid())
  );
