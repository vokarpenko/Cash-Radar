-- Foundation for profiles, shared banks, user accounts and user-owned categories.
-- Business transactions and calculated balances are introduced in later stages.

create schema private;
revoke all on schema private from public, anon, authenticated;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (display_name is null or length(btrim(display_name)) between 1 and 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.banks (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null check (length(btrim(name)) between 1 and 120),
  created_at timestamptz not null default now()
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  bank_id uuid references public.banks (id),
  name text not null check (length(btrim(name)) between 1 and 120),
  account_type text not null check (account_type in ('bank', 'cash', 'other')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  initial_balance numeric not null default 0 check (
    initial_balance > -1000000000000000000 and
    initial_balance < 1000000000000000000 and
    initial_balance = trunc(initial_balance, 4)
  ),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint account_bank_matches_type check (
    (account_type = 'bank' and bank_id is not null) or
    (account_type in ('cash', 'other') and bank_id is null)
  )
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  parent_id uuid,
  name text not null check (length(btrim(name)) between 1 and 120),
  kind text not null check (kind in ('expense', 'income', 'transfer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint categories_owner_id_unique unique (user_id, id),
  constraint categories_parent_same_owner foreign key (user_id, parent_id)
    references public.categories (user_id, id),
  constraint categories_not_own_parent check (parent_id is distinct from id)
);

create index accounts_user_active_idx on public.accounts (user_id, is_active);
create index accounts_bank_idx on public.accounts (bank_id);
create index categories_user_parent_idx on public.categories (user_id, parent_id);

alter table public.profiles enable row level security;
alter table public.banks enable row level security;
alter table public.accounts enable row level security;
alter table public.categories enable row level security;

-- RLS does not revoke PostgreSQL grants; explicitly narrow both.
revoke all on public.profiles, public.banks, public.accounts, public.categories
  from public, anon, authenticated;
grant select on public.profiles, public.banks, public.accounts, public.categories to authenticated;
grant update (display_name) on public.profiles to authenticated;
grant insert (bank_id, name, account_type, currency, initial_balance, is_active)
  on public.accounts to authenticated;
grant update (bank_id, name, account_type, currency, initial_balance, is_active)
  on public.accounts to authenticated;
grant insert (parent_id, name, kind) on public.categories to authenticated;
grant update (parent_id, name, kind) on public.categories to authenticated;
grant delete on public.categories to authenticated;
grant all on public.profiles, public.banks, public.accounts, public.categories to service_role;

create policy profiles_read_own on public.profiles for select to authenticated
  using ((select auth.uid()) = id);
create policy profiles_update_own on public.profiles for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy banks_read_authenticated on public.banks for select to authenticated
  using (true);
create policy accounts_read_own on public.accounts for select to authenticated
  using ((select auth.uid()) = user_id);
create policy accounts_insert_own on public.accounts for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy accounts_update_own on public.accounts for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy categories_read_own on public.categories for select to authenticated
  using ((select auth.uid()) = user_id);
create policy categories_insert_own on public.categories for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy categories_update_own on public.categories for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy categories_delete_own on public.categories for delete to authenticated
  using ((select auth.uid()) = user_id);

create function private.touch_updated_at()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at before update on public.profiles
  for each row execute function private.touch_updated_at();
create trigger accounts_touch_updated_at before update on public.accounts
  for each row execute function private.touch_updated_at();
create trigger categories_touch_updated_at before update on public.categories
  for each row execute function private.touch_updated_at();

-- Serialize parent changes for each owner so concurrent edits cannot create cycles.
create function private.check_category_ancestry()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.parent_id is null then
    return new;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text, 0));
  if exists (
    with recursive ancestors (id, parent_id) as (
      select c.id, c.parent_id from public.categories c
      where c.user_id = new.user_id and c.id = new.parent_id
      union
      select c.id, c.parent_id from public.categories c
      join ancestors a on c.id = a.parent_id
      where c.user_id = new.user_id
    )
    select 1 from ancestors where id = new.id
  ) then
    raise exception 'Category hierarchy cannot contain a cycle' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger categories_check_ancestry before insert or update of parent_id on public.categories
  for each row execute function private.check_category_ancestry();

insert into public.banks (code, name) values
  ('alfa_ru', 'Альфа-Банк'),
  ('acba_am', 'ACBA Bank'),
  ('ameria_am', 'Ameria Bank');

-- Private security-definer functions insert only fixed defaults for an Auth user.
create function private.create_user_defaults(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (p_user_id);
  insert into public.categories (user_id, name, kind) values
    (p_user_id, 'Продукты', 'expense'),
    (p_user_id, 'Рестораны', 'expense'),
    (p_user_id, 'Транспорт', 'expense'),
    (p_user_id, 'Такси', 'expense'),
    (p_user_id, 'Автомобиль', 'expense'),
    (p_user_id, 'Жильё', 'expense'),
    (p_user_id, 'Коммунальные услуги', 'expense'),
    (p_user_id, 'Связь', 'expense'),
    (p_user_id, 'Покупки', 'expense'),
    (p_user_id, 'Развлечения', 'expense'),
    (p_user_id, 'Здоровье', 'expense'),
    (p_user_id, 'Путешествия', 'expense'),
    (p_user_id, 'Зарплата', 'income'),
    (p_user_id, 'Переводы', 'transfer'),
    (p_user_id, 'Прочие доходы', 'income'),
    (p_user_id, 'Прочие расходы', 'expense');
end;
$$;

create function private.on_auth_user_created()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.create_user_defaults(new.id);
  return new;
end;
$$;

revoke all on function private.touch_updated_at() from public, anon, authenticated;
revoke all on function private.check_category_ancestry() from public, anon, authenticated;
revoke all on function private.create_user_defaults(uuid) from public, anon, authenticated;
revoke all on function private.on_auth_user_created() from public, anon, authenticated;

create trigger cash_radar_create_user_defaults after insert on auth.users
  for each row execute function private.on_auth_user_created();

-- Account created before this migration receives the same initial data.
select private.create_user_defaults(id) from auth.users;
