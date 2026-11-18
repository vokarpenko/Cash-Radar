\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role) values
 ('86000000-0000-4000-8000-000000000001','analytics-a@example.test','authenticated','authenticated'),
 ('86000000-0000-4000-8000-000000000002','analytics-b@example.test','authenticated','authenticated');
insert into public.accounts(id,user_id,name,account_type,currency,initial_balance) values
 ('86100000-0000-4000-8000-000000000001','86000000-0000-4000-8000-000000000001','Wallet','cash','AMD',1000),
 ('86100000-0000-4000-8000-000000000002','86000000-0000-4000-8000-000000000001','Cash','cash','AMD',0);
select set_config('request.jwt.claims','{"sub":"86000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
insert into public.transactions(account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency)
select '86100000-0000-4000-8000-000000000001',id,'expense','2026-11-04',10,'USD',4000,'AMD'
from public.categories where user_id=(select auth.uid()) and kind='expense' order by id limit 1;
select public.create_manual_transfer('86100000-0000-4000-8000-000000000001','86100000-0000-4000-8000-000000000002','2026-11-01',100,100,2,'Synthetic movement','86200000-0000-4000-8000-000000000001');
do $$ begin
 if (select sum(operation_count) from public.monthly_analytics_activity('2026-11-01')) <> 2 then raise exception 'Transfer was counted or fee omitted'; end if;
 if not exists(select 1 from public.monthly_analytics_activity('2026-11-01') where currency='USD' and amount::numeric=10 and account_amount::numeric=4000) then raise exception 'Actual account amount lost'; end if;
 if (select sum(operation_count) from public.period_analytics_activity('2026-11-01','2026-11-30')) <> 2 then raise exception 'Period included transfers or omitted fee'; end if;
 if not exists(select 1 from public.period_analytics_activity('2026-11-04','2026-11-04') where currency='USD' and amount::numeric=10 and account_amount::numeric=4000 and account_name='Wallet') then raise exception 'Period lost account or actual amount'; end if;
 if exists(select 1 from public.period_analytics_activity('2026-11-05','2026-11-05')) then raise exception 'Period includes a different date'; end if;
 begin perform * from public.period_analytics_activity('2026-11-05','2026-11-04'); raise exception 'Reversed period accepted'; exception when invalid_parameter_value then null; end;
 if exists(select 1 from public.monthly_analytics_activity('2026-12-01')) then raise exception 'Wrong month included'; end if;
 begin perform * from public.monthly_analytics_activity('2026-11-02'); raise exception 'Invalid date accepted'; exception when invalid_parameter_value then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"86000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ begin if exists(select 1 from public.monthly_analytics_activity('2026-11-01')) or exists(select 1 from public.period_analytics_activity('2026-11-01','2026-11-30')) then raise exception 'Foreign transactions visible'; end if; end $$;
rollback;
