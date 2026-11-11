-- Owner and currency are included in foreign keys so neither a foreign account nor
-- a later account-currency change can silently reinterpret a financial operation.
alter table public.accounts add constraint accounts_owner_id_currency_unique
  unique (user_id, id, currency);
alter table public.categories add constraint categories_owner_id_kind_unique
  unique (user_id, id, kind);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  account_id uuid not null,
  category_id uuid not null,
  transaction_type text not null check (transaction_type in ('income', 'expense')),
  transaction_date date not null,
  amount numeric not null check (amount > 0 and amount < 1000000000000000000 and amount = trunc(amount, 4)),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  account_amount numeric not null check (account_amount > 0 and account_amount < 1000000000000000000 and account_amount = trunc(account_amount, 4)),
  account_currency text not null check (account_currency ~ '^[A-Z]{3}$'),
  raw_description text check (raw_description is null or length(btrim(raw_description)) between 1 and 500),
  source text not null default 'manual' check (source = 'manual'),
  status text not null default 'confirmed' check (status = 'confirmed'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transaction_account_owner_currency_fk foreign key (user_id, account_id, account_currency)
    references public.accounts(user_id, id, currency),
  constraint transaction_category_owner_kind_fk foreign key (user_id, category_id, transaction_type)
    references public.categories(user_id, id, kind),
  constraint transaction_same_currency_same_amount check (currency <> account_currency or amount = account_amount)
);
create index transactions_owner_account_idx on public.transactions(user_id, account_id);
create index transactions_owner_date_idx on public.transactions(user_id, transaction_date desc, id);
create index transactions_owner_category_idx on public.transactions(user_id, category_id);

alter table public.transactions enable row level security;
revoke all on public.transactions from public, anon, authenticated;
grant select, delete on public.transactions to authenticated;
grant insert (account_id, category_id, transaction_type, transaction_date, amount, currency, account_amount, account_currency, raw_description)
  on public.transactions to authenticated;
grant update (account_id, category_id, transaction_type, transaction_date, amount, currency, account_amount, account_currency, raw_description)
  on public.transactions to authenticated;
grant all on public.transactions to service_role;
create policy transactions_read_own on public.transactions for select to authenticated using ((select auth.uid()) = user_id);
create policy transactions_insert_own on public.transactions for insert to authenticated with check ((select auth.uid()) = user_id);
create policy transactions_update_own on public.transactions for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy transactions_delete_own on public.transactions for delete to authenticated using ((select auth.uid()) = user_id);
create trigger transactions_touch_updated_at before update on public.transactions
  for each row execute function private.touch_updated_at();

create or replace view public.account_balances with (security_invoker = true) as
select a.id, a.name, a.account_type, a.bank_id, b.name as bank_name,
       a.currency, a.initial_balance::text as initial_balance,
       (a.initial_balance + coalesce((select sum(case when t.transaction_type = 'income' then t.account_amount else -t.account_amount end)
          from public.transactions t where t.user_id = a.user_id and t.account_id = a.id), 0))::text as current_balance,
       a.is_active, a.created_at,
       exists(select 1 from public.transactions t where t.user_id = a.user_id and t.account_id = a.id) as has_transactions
from public.accounts a left join public.banks b on b.id = a.bank_id;

create view public.transaction_details with (security_invoker = true) as
select t.id, t.account_id, a.name as account_name, a.is_active as account_active,
       t.category_id, c.name as category_name, t.transaction_type, t.transaction_date,
       t.amount::text as amount, t.currency, t.account_amount::text as account_amount,
       t.account_currency, t.raw_description, t.source, t.status, t.created_at
from public.transactions t
join public.accounts a on a.user_id = t.user_id and a.id = t.account_id
join public.categories c on c.user_id = t.user_id and c.id = t.category_id;
revoke all on public.transaction_details from public, anon, authenticated;
grant select on public.transaction_details to authenticated;
grant all on public.transaction_details to service_role;
