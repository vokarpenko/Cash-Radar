\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role) values
 ('85000000-0000-4000-8000-000000000001','budget-a@example.test','authenticated','authenticated'),
 ('85000000-0000-4000-8000-000000000002','budget-b@example.test','authenticated','authenticated');
insert into public.categories(id,user_id,name,kind) values
 ('85000000-0000-4000-8000-000000000011','85000000-0000-4000-8000-000000000001','Synthetic expense','expense'),
 ('85000000-0000-4000-8000-000000000012','85000000-0000-4000-8000-000000000001','Synthetic income','income'),
 ('85000000-0000-4000-8000-000000000013','85000000-0000-4000-8000-000000000002','Foreign expense','expense');
select set_config('request.jwt.claims','{"sub":"85000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 perform public.save_budget_version('85000000-0000-4000-8000-000000000011','2026-01-01','AMD',1000.25);
 perform public.save_budget_version('85000000-0000-4000-8000-000000000011','2026-03-01','RUB',500.5);
 if not exists(select 1 from public.effective_monthly_budgets('2026-02-01') where amount::numeric=1000.25 and currency='AMD') then raise exception 'Previous budget missing from summary'; end if;
 if not exists(select 1 from public.effective_monthly_budgets('2026-04-01') where amount::numeric=500.5 and currency='RUB') then raise exception 'Recurring budget missing from summary'; end if;
 if (select amount from public.budget_versions where effective_month <= '2026-02-01' order by effective_month desc limit 1) <> 1000.25 then raise exception 'Budget history changed'; end if;
 if (select amount from public.budget_versions where effective_month <= '2026-04-01' order by effective_month desc limit 1) <> 500.5 then raise exception 'Budget did not recur'; end if;
 perform public.save_budget_version('85000000-0000-4000-8000-000000000011','2026-05-01','RUB',null);
 if exists(select 1 from public.effective_monthly_budgets('2026-06-01')) then raise exception 'Disabled budget visible in summary'; end if;
 if (select amount from public.budget_versions where effective_month <= '2026-06-01' order by effective_month desc limit 1) is not null then raise exception 'Stopped budget recurred'; end if;
 begin perform public.save_budget_version('85000000-0000-4000-8000-000000000012','2026-01-01','AMD',10); raise exception 'Income category accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.save_budget_version('85000000-0000-4000-8000-000000000013','2026-01-01','AMD',10); raise exception 'Foreign category accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.save_budget_version('85000000-0000-4000-8000-000000000011','2026-01-02','AMD',10); raise exception 'Invalid month accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.save_budget_version('85000000-0000-4000-8000-000000000011','2026-01-01','AMD',1.001); raise exception 'Invalid precision accepted'; exception when invalid_parameter_value then null; end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"85000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.budget_versions) or exists(select 1 from public.effective_monthly_budgets('2026-04-01')) then raise exception 'Foreign budgets visible'; end if;
end $$;
reset role;
rollback;
