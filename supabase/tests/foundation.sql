-- Run against an isolated local Supabase database. All fixtures roll back.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, aud, role)
values
  ('10000000-0000-4000-8000-000000000001', 'stage3-a@example.test', 'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000002', 'stage3-b@example.test', 'authenticated', 'authenticated');

do $$
begin
  if (select count(*) from public.profiles where id in (
    '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002'
  )) <> 2 then raise exception 'User profile bootstrap failed'; end if;
  if (select count(*) from public.categories where user_id = '10000000-0000-4000-8000-000000000001') <> 16
    or (select count(*) from public.categories where user_id = '10000000-0000-4000-8000-000000000002') <> 16
  then raise exception 'Default category bootstrap failed'; end if;
  if (select count(*) from public.banks) <> 3 then raise exception 'Bank seed failed'; end if;
  if exists (select 1 from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname in ('profiles','banks','accounts','categories') and not c.relrowsecurity)
  then raise exception 'RLS is not enabled'; end if;
  if has_table_privilege('anon', 'public.profiles', 'select')
    or has_table_privilege('anon', 'public.banks', 'select')
    or has_table_privilege('anon', 'public.accounts', 'select')
    or has_table_privilege('anon', 'public.categories', 'select')
  then raise exception 'Anonymous role can read data'; end if;
  if has_table_privilege('authenticated', 'public.banks', 'insert')
    or has_table_privilege('authenticated', 'public.accounts', 'delete')
    or has_column_privilege('authenticated', 'public.accounts', 'user_id', 'update')
    or has_column_privilege('authenticated', 'public.categories', 'user_id', 'update')
    or has_column_privilege('authenticated', 'public.profiles', 'id', 'update')
  then raise exception 'Unexpected authenticated privilege'; end if;
end;
$$;

insert into public.accounts (id, user_id, name, account_type, currency, initial_balance)
values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Wallet A', 'cash', 'AMD', 10.1234),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'Wallet B', 'cash', 'RUB', -5.50);
select pg_catalog.set_config('test.category_a', (select id::text from public.categories where user_id = '10000000-0000-4000-8000-000000000001' and name = 'Продукты'), true);
select pg_catalog.set_config('test.category_b', (select id::text from public.categories where user_id = '10000000-0000-4000-8000-000000000002' and name = 'Продукты'), true);
select pg_catalog.set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  root_id uuid := current_setting('test.category_a')::uuid;
  foreign_id uuid := current_setting('test.category_b')::uuid;
  child_id uuid;
  changed integer;
begin
  if (select count(*) from public.profiles) <> 1 then raise exception 'Profile isolation failed'; end if;
  if (select count(*) from public.categories) <> 16 then raise exception 'Category isolation failed'; end if;
  if (select count(*) from public.accounts) <> 1 then raise exception 'Account isolation failed'; end if;
  if (select count(*) from public.banks) <> 3 then raise exception 'Authenticated user cannot read banks'; end if;

  update public.profiles set display_name = 'Owner A' where id = '10000000-0000-4000-8000-000000000001';
  get diagnostics changed = row_count;
  if changed <> 1 then raise exception 'Own profile update failed'; end if;
  update public.profiles set display_name = 'Owner A' where id = '10000000-0000-4000-8000-000000000002';
  get diagnostics changed = row_count;
  if changed <> 0 then raise exception 'Other profile was updated'; end if;
  update public.accounts set name = 'Stolen' where id = '20000000-0000-4000-8000-000000000002';
  get diagnostics changed = row_count;
  if changed <> 0 then raise exception 'Other account was updated'; end if;
  delete from public.categories where id = foreign_id;
  get diagnostics changed = row_count;
  if changed <> 0 then raise exception 'Other category was deleted'; end if;

  insert into public.accounts (name, account_type, currency, initial_balance) values ('Own wallet', 'cash', 'EUR', -7.1250);
  if (select count(*) from public.accounts) <> 2 then raise exception 'Own account insertion failed'; end if;
  begin
    insert into public.accounts (user_id, name, account_type, currency)
      values ('10000000-0000-4000-8000-000000000002', 'Spoofed', 'cash', 'AMD');
    raise exception 'User could spoof account owner';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.accounts (name, account_type, currency, initial_balance) values ('Invalid precision', 'cash', 'AMD', 0.00001);
    raise exception 'Excess fractional precision accepted';
  exception when check_violation then null; end;
  begin
    insert into public.accounts (name, account_type, currency, initial_balance) values ('Not a number', 'cash', 'AMD', 'NaN'::numeric);
    raise exception 'Non-finite balance accepted';
  exception when check_violation then null; end;
  begin
    insert into public.accounts (name, account_type, currency, initial_balance) values ('Out of range', 'cash', 'AMD', 1000000000000000000);
    raise exception 'Out-of-range balance accepted';
  exception when check_violation then null; end;
  begin
    insert into public.accounts (name, account_type, currency) values ('Invalid bank account', 'bank', 'AMD');
    raise exception 'Bank account without bank accepted';
  exception when check_violation then null; end;
  begin
    insert into public.categories (parent_id, name, kind) values (foreign_id, 'Cross-user child', 'expense');
    raise exception 'Cross-user parent accepted';
  exception when foreign_key_violation then null; end;
  begin
    insert into public.categories (user_id, name, kind)
      values ('10000000-0000-4000-8000-000000000002', 'Spoofed category', 'expense');
    raise exception 'User could spoof category owner';
  exception when insufficient_privilege then null; end;
  insert into public.categories (parent_id, name, kind) values (root_id, 'Own child', 'expense') returning id into child_id;
  begin
    update public.categories set parent_id = child_id where id = root_id;
    raise exception 'Category cycle accepted';
  exception when check_violation then null; end;
  update public.categories set name = 'My category' where id = root_id;
  get diagnostics changed = row_count;
  if changed <> 1 then raise exception 'Own category update failed'; end if;
end;
$$;

reset role;
select pg_catalog.set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
  if (select count(*) from public.profiles) <> 1 or (select count(*) from public.accounts) <> 1
    or (select count(*) from public.categories) <> 16
  then raise exception 'User B isolation failed'; end if;
end;
$$;
reset role;

-- Deleting an Auth user must also remove their profile, accounts and hierarchy.
delete from auth.users where id = '10000000-0000-4000-8000-000000000001';
do $$
begin
  if exists (select 1 from public.profiles where id = '10000000-0000-4000-8000-000000000001')
    or exists (select 1 from public.accounts where user_id = '10000000-0000-4000-8000-000000000001')
    or exists (select 1 from public.categories where user_id = '10000000-0000-4000-8000-000000000001')
  then raise exception 'Auth user deletion left related rows'; end if;
end;
$$;
rollback;
