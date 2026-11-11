-- Account balances are exposed as decimal strings to preserve exact precision in Web.
-- Transactions do not exist yet; the current balance is the opening balance.
alter table public.profiles
  add column base_currency text not null default 'AMD'
  check (base_currency ~ '^[A-Z]{3}$');

grant update (base_currency) on public.profiles to authenticated;

create view public.account_balances
with (security_invoker = true) as
select a.id, a.name, a.account_type, a.bank_id, b.name as bank_name,
       a.currency, a.initial_balance::text as initial_balance,
       a.initial_balance::text as current_balance,
       a.is_active, a.created_at
from public.accounts a
left join public.banks b on b.id = a.bank_id;

revoke all on public.account_balances from public, anon, authenticated;
grant select on public.account_balances to authenticated;
grant all on public.account_balances to service_role;
