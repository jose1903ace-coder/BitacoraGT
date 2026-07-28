-- Wedding Planner · Esquema de base de datos (Supabase)
-- Proyecto: pnlefnwngmktiykelkdd (aplicado como migraciones:
--   wedding_planner_schema, wp_lock_down_trigger_fn, wp_rename_hotel_to_venue,
--   wp_add_photo_category, wp_provider_plans, wp_admin_set_plan_rpc,
--   wp_images_bucket, wp_profile_email, wp_reviews)
-- Este archivo es una copia de referencia del esquema en producción.

create table if not exists public.wp_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('provider','client')),
  full_name text not null,
  phone text,
  email text,
  plan text not null default 'free' check (plan in ('free','premium')),
  plan_expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.wp_listings (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.wp_profiles(id) on delete cascade,
  category text not null check (category in ('venue','planner','florist','photo','furniture')),
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
  insert into public.wp_profiles (id, role, full_name, phone, email)
  values (
    new.id,
    case when new.raw_user_meta_data->>'role' = 'provider' then 'provider' else 'client' end,
    coalesce(nullif(new.raw_user_meta_data->>'full_name',''), new.email),
    nullif(new.raw_user_meta_data->>'phone',''),
    new.email
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

-- Planes de proveedor: free = 1 anuncio activo; premium ("Destacado") = ilimitado
create or replace function public.wp_is_premium(p uuid)
returns boolean
language sql stable
as $$
  select exists (
    select 1 from public.wp_profiles
    where id = p and plan = 'premium'
      and (plan_expires_at is null or plan_expires_at > now())
  );
$$;

create or replace function public.wp_enforce_listing_limit()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.active and not public.wp_is_premium(new.provider_id) then
    if (select count(*) from public.wp_listings
        where provider_id = new.provider_id and active and id <> new.id) >= 1 then
      raise exception 'PLAN_LIMIT';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.wp_enforce_listing_limit() from public, anon, authenticated;

drop trigger if exists wp_listing_limit on public.wp_listings;
create trigger wp_listing_limit
  before insert or update of active on public.wp_listings
  for each row execute function public.wp_enforce_listing_limit();

-- Solo el administrador (SQL / dashboard con service role) puede cambiar el plan
create or replace function public.wp_protect_plan_columns()
returns trigger
language plpgsql
as $$
begin
  if current_setting('request.jwt.claims', true) is not null
     and coalesce(current_setting('request.jwt.claims', true)::jsonb->>'role','') = 'authenticated'
     and (new.plan is distinct from old.plan or new.plan_expires_at is distinct from old.plan_expires_at) then
    raise exception 'PLAN_PROTECTED';
  end if;
  return new;
end;
$$;

revoke execute on function public.wp_protect_plan_columns() from public, anon, authenticated;

drop trigger if exists wp_protect_plan on public.wp_profiles;
create trigger wp_protect_plan
  before update on public.wp_profiles
  for each row execute function public.wp_protect_plan_columns();

-- RPC de administración (la llama la edge function wp-admin-plan con
-- service_role): activa/desactiva el plan Destacado por correo del proveedor
create or replace function public.wp_admin_set_plan(p_email text, p_days int)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid;
  nombre text;
  vence timestamptz;
begin
  select id into uid from auth.users where lower(email) = lower(p_email);
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'no_user');
  end if;
  if p_days is null or p_days <= 0 then
    update public.wp_profiles set plan = 'free', plan_expires_at = null
    where id = uid returning full_name into nombre;
  else
    vence := now() + make_interval(days => p_days);
    update public.wp_profiles set plan = 'premium', plan_expires_at = vence
    where id = uid returning full_name into nombre;
  end if;
  if nombre is null then
    return jsonb_build_object('ok', false, 'error', 'no_profile');
  end if;
  return jsonb_build_object('ok', true, 'name', nombre,
    'plan', case when coalesce(p_days,0) > 0 then 'premium' else 'free' end,
    'expires', vence);
end;
$$;

revoke execute on function public.wp_admin_set_plan(text, int) from public, anon, authenticated;

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

-- Reseñas: 1-5 estrellas + comentario corto. Solo parejas con una solicitud
-- aceptada en ese anuncio; una reseña por pareja por anuncio.
create table if not exists public.wp_reviews (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.wp_listings(id) on delete cascade,
  client_id uuid not null references public.wp_profiles(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 300),
  created_at timestamptz not null default now(),
  unique (listing_id, client_id)
);

create index if not exists wp_reviews_listing_idx on public.wp_reviews(listing_id);

alter table public.wp_reviews enable row level security;

create policy "wp_reviews_select" on public.wp_reviews for select using (true);
create policy "wp_reviews_insert_client" on public.wp_reviews for insert
  with check (
    auth.uid() = client_id
    and exists (
      select 1 from public.wp_bookings b
      where b.listing_id = wp_reviews.listing_id
        and b.client_id = auth.uid()
        and b.status = 'accepted'
    )
  );
create policy "wp_reviews_update_own" on public.wp_reviews for update
  using (auth.uid() = client_id)
  with check (auth.uid() = client_id);
create policy "wp_reviews_delete_own" on public.wp_reviews for delete
  using (auth.uid() = client_id);

-- Fotos de anuncios: bucket público 'wp-images' (máx 5 MB, solo imágenes).
-- Cada usuario sube a su carpeta (auth.uid()); lectura pública; borra el dueño.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('wp-images','wp-images', true, 5242880,
        array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do nothing;

create policy "wp_images_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'wp-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "wp_images_update" on storage.objects for update to authenticated
  using (bucket_id = 'wp-images' and owner = auth.uid());
create policy "wp_images_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'wp-images' and owner = auth.uid());
create policy "wp_images_read" on storage.objects for select
  using (bucket_id = 'wp-images');
