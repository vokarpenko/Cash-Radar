-- Aggregate exact amounts without exposing individual descriptions to a rate provider.
create function public.monthly_analytics_activity(p_month date)
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
 group by t.category_id,c.name,t.transaction_type,t.transaction_date,t.currency,t.account_currency,a.bank_id
 order by c.name,t.category_id,t.transaction_type,t.transaction_date,t.currency,t.account_currency,a.bank_id;
end $$;
revoke all on function public.monthly_analytics_activity(date) from public,anon,authenticated;
grant execute on function public.monthly_analytics_activity(date) to authenticated;

create function public.effective_monthly_budgets(p_month date)
returns table(category_id uuid, category_name text, currency text, amount text)
language plpgsql stable security invoker set search_path = '' as $$
begin
 if (select auth.uid()) is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_month is null or p_month <> date_trunc('month',p_month)::date or p_month < date '1900-01-01' or p_month >= date '2101-01-01' then
   raise exception 'Invalid month' using errcode='22023';
 end if;
 return query
 select b.category_id,c.name,b.currency,b.amount::text
 from (select distinct on (v.category_id) v.category_id,v.currency,v.amount
       from public.budget_versions v where v.user_id=(select auth.uid()) and v.effective_month<=p_month
       order by v.category_id,v.effective_month desc) b
 join public.categories c on c.user_id=(select auth.uid()) and c.id=b.category_id
 where b.amount is not null order by c.name,b.category_id;
end $$;
revoke all on function public.effective_monthly_budgets(date) from public,anon,authenticated;
grant execute on function public.effective_monthly_budgets(date) to authenticated;
