\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role) values
 ('80000000-0000-4000-8000-000000000001','stage11-a@example.test','authenticated','authenticated'),
 ('80000000-0000-4000-8000-000000000002','stage11-b@example.test','authenticated','authenticated');
insert into public.accounts(id,user_id,name,account_type,currency,initial_balance) values
 ('81000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000001','A','cash','AMD',100),
 ('81000000-0000-4000-8000-000000000002','80000000-0000-4000-8000-000000000002','B','cash','AMD',100);
select set_config('test.cat',(select id::text from public.categories where user_id='80000000-0000-4000-8000-000000000001' and name='Прочие расходы'),true);
insert into public.transactions(user_id,account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description)
values ('80000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001',current_setting('test.cat')::uuid,'expense','2026-11-01',10,'AMD',10,'AMD','TEST   MERCHANT');
select set_config('test.data',jsonb_build_array(
 jsonb_build_object('row_number',2,'transaction_date','2026-11-02','transaction_type','expense','amount','10.00','currency','AMD','account_amount','10.00','category_id',current_setting('test.cat'),'raw_description','test merchant','raw_data','{}'::jsonb,'commission_amount','2.00','commission_category_id',current_setting('test.cat')),
 jsonb_build_object('row_number',3,'transaction_date','2026-11-03','transaction_type','expense','amount','5.00','currency','AMD','account_amount','5.00','category_id',current_setting('test.cat'),'raw_description','Other merchant','raw_data','{}'::jsonb)
)::text,true);
select set_config('test.batch',(public.register_statement_import('80000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','AMD','fixture.csv',repeat('1',64),current_setting('test.data')::jsonb,'[]',0,'cashradar_csv_v1')->>'id'),true);
select set_config('test.item',(select id::text from public.import_items where batch_id=current_setting('test.batch')::uuid and row_number=2),true);
select set_config('request.jwt.claims','{"sub":"80000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.import_duplicate_candidates where batch_id=current_setting('test.batch')::uuid) then raise exception 'foreign candidate visible'; end if;
 begin perform public.resolve_import_duplicate(current_setting('test.item')::uuid,'skip'); raise exception 'foreign decision allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"80000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare r jsonb; begin
 if (select candidate_count from public.import_item_details where id=current_setting('test.item')::uuid)<>1 then raise exception 'candidate missing'; end if;
 begin perform public.confirm_statement_import(current_setting('test.batch')::uuid); raise exception 'unreviewed accepted'; exception when invalid_parameter_value then null; end;
 perform public.resolve_import_duplicate(current_setting('test.item')::uuid,'skip');
 r:=public.confirm_statement_import(current_setting('test.batch')::uuid);
 if (r->>'imported_count')::integer<>1 or (r->>'duplicate_count')::integer<>1 then raise exception 'incorrect import counts'; end if;
 if (select current_balance::numeric from public.account_balances where id='81000000-0000-4000-8000-000000000001')<>85 then raise exception 'skipped row or its fee affected balance'; end if;
 if (select count(*) from public.deduplication_decisions where batch_id=current_setting('test.batch')::uuid and decision='skip')<>1 then raise exception 'missing audit decision'; end if;
 r:=public.confirm_statement_import(current_setting('test.batch')::uuid);
 if not (r->>'already_confirmed')::boolean then raise exception 'confirmation not idempotent'; end if;
end $$;
reset role;
-- A changed match invalidates the earlier review, even if it disappears completely.
select set_config('test.batch2',(public.register_statement_import('80000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','AMD','fixture2.csv',repeat('2',64),current_setting('test.data')::jsonb,'[]',0,'cashradar_csv_v1')->>'id'),true);
select set_config('test.item2',(select id::text from public.import_items where batch_id=current_setting('test.batch2')::uuid and row_number=2),true);
set local role authenticated;
do $$ begin
 perform public.resolve_import_duplicate(current_setting('test.item2')::uuid,'keep');
 update public.transactions set raw_description='Changed merchant' where user_id=(select auth.uid()) and raw_description='TEST   MERCHANT';
 begin perform public.confirm_statement_import(current_setting('test.batch2')::uuid); raise exception 'stale decision accepted'; exception when invalid_parameter_value then null; end;
 perform public.resolve_import_duplicate(current_setting('test.item2')::uuid,'clear');
 -- Another row is now a candidate because the earlier import was confirmed.
 if not exists(select 1 from public.import_item_details where batch_id=current_setting('test.batch2')::uuid and row_number=3 and candidate_count=1) then raise exception 'matching confirmed statement not found'; end if;
 perform public.resolve_import_duplicate((select id from public.import_item_details where batch_id=current_setting('test.batch2')::uuid and row_number=3),'skip');
 perform public.confirm_statement_import(current_setting('test.batch2')::uuid);
end $$;
reset role;
rollback;
