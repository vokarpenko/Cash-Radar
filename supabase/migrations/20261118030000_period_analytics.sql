-- Per-day, account and original-currency totals; transfer legs are not income or expense.
create function public.period_analytics_activity(p_start date, p_end date)
returns table(account_id uuid, account_name text, account_active boolean, category_id uuid, category_name text, transaction_date date,
 transaction_type text, currency text, account_currency text, operation_count bigint,
 amount text, account_amount text)
language plpgsql stable security invoker set search_path='' as $$
begin
 if (select auth.uid()) is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_start is null or p_end is null or p_start > p_end or p_start < date '1900-01-01' or p_end > date '2100-12-31' then
  raise exception 'Invalid period' using errcode='22023';
 end if;
 return query
 select a.id,a.name,a.is_active,c.id,c.name,t.transaction_date,t.transaction_type,t.currency,t.account_currency,
        count(*),sum(t.amount)::text,sum(t.account_amount)::text
 from public.transactions t
 join public.accounts a on a.user_id=t.user_id and a.id=t.account_id
 join public.categories c on c.user_id=t.user_id and c.id=t.category_id
 where t.user_id=(select auth.uid()) and t.status='confirmed'
   and t.transaction_date >= p_start and t.transaction_date <= p_end
   and not exists(select 1 from public.transfer_groups g where g.user_id=t.user_id and t.id in (g.debit_id,g.credit_id))
 group by a.id,a.name,a.is_active,c.id,c.name,t.transaction_date,t.transaction_type,t.currency,t.account_currency
 order by t.transaction_date,a.id,c.id,t.transaction_type,t.currency,t.account_currency;
end $$;
revoke all on function public.period_analytics_activity(date,date) from public,anon,authenticated;
grant execute on function public.period_analytics_activity(date,date) to authenticated;

-- Align per-account conversion rounding between monthly and period analytics.
-- Aggregate exact amounts without exposing individual descriptions to a rate provider.
create or replace function public.monthly_analytics_activity(p_month date)
returns table(category_id uuid, category_name text, transaction_type text, transaction_date date,
 currency text, account_currency text, bank_id uuid, operation_count bigint,
 amount text, account_amount text)
language plpgsql stable security invoker set search_path = '' as $$
begin
 if (select auth.uid()) is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_month is null or p_month <> date_trunc('month',p_month)::date or p_month < date '1900-01-01' or p_month >= date '2101-01-01' then
   raise exception 'Invalid month' using errcode='22023';
 end if;
 return query
 select t.category_id,c.name,t.transaction_type,t.transaction_date,t.currency,t.account_currency,a.bank_id,
        count(*),sum(t.amount)::text,sum(t.account_amount)::text
 from public.transactions t
 join public.categories c on c.user_id=t.user_id and c.id=t.category_id
 join public.accounts a on a.user_id=t.user_id and a.id=t.account_id
 where t.user_id=(select auth.uid()) and t.status='confirmed'
   and t.transaction_date >= p_month and t.transaction_date < (p_month + interval '1 month')::date
   and not exists(select 1 from public.transfer_groups g where g.user_id=t.user_id and t.id in(g.debit_id,g.credit_id))
 group by t.category_id,c.name,t.transaction_type,t.transaction_date,t.currency,t.account_currency,a.bank_id,a.id
 order by c.name,t.category_id,t.transaction_type,t.transaction_date,t.currency,t.account_currency,a.bank_id,a.id;
end $$;
revoke all on function public.monthly_analytics_activity(date) from public,anon,authenticated;
grant execute on function public.monthly_analytics_activity(date) to authenticated;
