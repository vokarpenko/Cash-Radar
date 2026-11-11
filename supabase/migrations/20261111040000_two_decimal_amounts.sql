-- Enforce two decimal places without rounding or modifying existing records.
-- PostgreSQL accepts equivalent values with trailing zeros, e.g. 1.2300.
alter table public.accounts add constraint accounts_initial_balance_two_decimals
  check (initial_balance = trunc(initial_balance, 2));
alter table public.transactions add constraint transactions_amount_two_decimals
  check (amount = trunc(amount, 2));
alter table public.transactions add constraint transactions_account_amount_two_decimals
  check (account_amount = trunc(account_amount, 2));
