\set ON_ERROR_STOP on
begin;
insert into auth.users (id,email,aud,role) values
 ('70000000-0000-4000-8000-000000000001','stage7-a@example.test','authenticated','authenticated'),
 ('70000000-0000-4000-8000-000000000002','stage7-b@example.test','authenticated','authenticated');
insert into public.accounts (id,user_id,name,account_type,currency,initial_balance) values
 ('71000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001','A','cash','AMD',100),
 ('71000000-0000-4000-8000-000000000002','70000000-0000-4000-8000-000000000002','B','cash','USD',100);
select set_config('test.stage7.category', (select id::text from public.categories where user_id = '70000000-0000-4000-8000-000000000001' and name = 'Продукты'), true);
select set_config('test.stage7.items', jsonb_build_array(
 jsonb_build_object('row_number',2,'transaction_date','2026-11-11','transaction_type','expense','amount','10.25','currency','AMD','account_amount','10.25','category_id',current_setting('test.stage7.category'),'raw_description','Test','raw_data',jsonb_build_object('description','Test')),
 jsonb_build_object('row_number',3,'transaction_date','2026-11-12','transaction_type','expense','amount','2.00','currency','EUR','account_amount','15.10','category_id',current_setting('test.stage7.category'),'raw_description',null,'raw_data',jsonb_build_object('description',''))
)::text, true);
do $$
begin
 if has_function_privilege('authenticated','public.register_statement_import(uuid,uuid,text,text,text,jsonb,jsonb,integer)','execute') then raise exception 'Client can forge import'; end if;
 if has_table_privilege('authenticated','public.import_batches','insert') or has_table_privilege('authenticated','public.import_items','update') then raise exception 'Client can mutate staged data'; end if;
 if has_table_privilege('anon','public.import_batches','select') or has_table_privilege('anon','public.import_item_details','select') then raise exception 'Anonymous access'; end if;
end; $$;
select set_config('test.stage7.result', public.register_statement_import(
 '70000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','AMD','fixture.csv',repeat('a',64),current_setting('test.stage7.items')::jsonb,'[]'::jsonb,0)::text, true);
select set_config('test.stage7.batch', (current_setting('test.stage7.result')::jsonb ->> 'id'), true);
do $$ declare result jsonb; begin
 result := public.register_statement_import('70000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','AMD','fixture.csv',repeat('a',64),current_setting('test.stage7.items')::jsonb,'[]'::jsonb,0);
 if result->>'id' <> current_setting('test.stage7.batch') or (result->>'duplicate')::boolean is not true then raise exception 'Duplicate not detected'; end if;
 result := public.register_statement_import('70000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','AMD','invalid.csv',repeat('b',64),'[]'::jsonb,'[{"row":2,"message":"Invalid"}]'::jsonb,1);
 if result->>'status' <> 'invalid' then raise exception 'Invalid batch state'; end if;
 result := public.register_statement_import('70000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','AMD','invalid.csv',repeat('b',64),current_setting('test.stage7.items')::jsonb,'[]'::jsonb,0);
 if result->>'status' <> 'ready' or (result->>'duplicate')::boolean then raise exception 'Retry rejected'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"70000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if (select count(*) from public.import_batches) <> 0 or (select count(*) from public.import_item_details) <> 0 then raise exception 'Import RLS failed'; end if;
 begin perform public.confirm_statement_import(current_setting('test.stage7.batch')::uuid); raise exception 'Foreign confirmation allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"70000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare r jsonb; begin
 if (select count(*) from public.import_item_details where batch_id=current_setting('test.stage7.batch')::uuid) <> 2 then raise exception 'Preview missing'; end if;
 r:=public.confirm_statement_import(current_setting('test.stage7.batch')::uuid);
 if (r->>'imported_count')::int <> 2 or (r->>'already_confirmed')::boolean then raise exception 'Confirmation failed'; end if;
 r:=public.confirm_statement_import(current_setting('test.stage7.batch')::uuid);
 if (r->>'imported_count')::int <> 2 or (r->>'already_confirmed')::boolean is not true then raise exception 'Repeated confirmation not idempotent'; end if;
 if (select count(*) from public.transactions where import_batch_id = current_setting('test.stage7.batch')::uuid) <> 2 then raise exception 'Duplicate transaction'; end if;
 if (select current_balance from public.account_balances where id='71000000-0000-4000-8000-000000000001')::numeric <> 74.65 then raise exception 'Wrong balance'; end if;
end $$;
reset role;
delete from auth.users where id='70000000-0000-4000-8000-000000000001';
rollback;
