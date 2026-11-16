\set ON_ERROR_STOP on
begin;
insert into auth.users (id,email,aud,role) values
 ('80000000-0000-4000-8000-000000000001','alfa-a@example.test','authenticated','authenticated'),
 ('80000000-0000-4000-8000-000000000002','alfa-b@example.test','authenticated','authenticated');
insert into public.accounts (id,user_id,name,account_type,currency,initial_balance,bank_id) values
 ('81000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000001','Alfa','bank','RUB',100,(select id from public.banks where code='alfa_ru')),
 ('81000000-0000-4000-8000-000000000002','80000000-0000-4000-8000-000000000001','Other','bank','RUB',100,(select id from public.banks where code='ameria_am'));
select set_config('test.alfa.items',jsonb_build_array(jsonb_build_object(
 'row_number',21,'transaction_date','2026-11-01','transaction_type','expense','amount','10.25','currency','RUB','account_amount','10.25',
 'category_id',(select id from public.categories where user_id='80000000-0000-4000-8000-000000000001' and name='Прочие расходы'),
 'raw_description','Synthetic shop','raw_data',jsonb_build_object('posting_date','2026-11-02','bank_operation_code','TEST001','mcc','5411')))::text,true);
do $$ begin
 begin
  perform public.register_statement_import('80000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002','RUB','test.xlsx',repeat('c',64),current_setting('test.alfa.items')::jsonb,'[]',0,'alfa_xlsx_v1');
  raise exception 'Alfa imported to wrong bank';
 exception when invalid_parameter_value then null; end;
end $$;
select set_config('test.alfa.batch',(public.register_statement_import('80000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','RUB','test.xlsx',repeat('d',64),current_setting('test.alfa.items')::jsonb,'[]',0,'alfa_xlsx_v1')->>'id'),true);
select set_config('request.jwt.claims','{"sub":"80000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.import_item_details where batch_id=current_setting('test.alfa.batch')::uuid) then raise exception 'Alfa preview visible to another user'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"80000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare r jsonb; begin
 if not exists(select 1 from public.import_item_details where batch_id=current_setting('test.alfa.batch')::uuid and posting_date='2026-11-02' and bank_operation_code='TEST001' and mcc='5411' and not original_amount_known) then raise exception 'Missing Alfa preview metadata'; end if;
 r:=public.confirm_statement_import(current_setting('test.alfa.batch')::uuid);
 if (r->>'imported_count')::int<>1 then raise exception 'Alfa confirmation failed'; end if;
 if not exists(select 1 from public.transaction_details where posting_date='2026-11-02' and bank_operation_code='TEST001' and mcc='5411' and not original_amount_known) then raise exception 'Alfa transaction metadata lost'; end if;
 r:=public.confirm_statement_import(current_setting('test.alfa.batch')::uuid);
 if not (r->>'already_confirmed')::boolean then raise exception 'Alfa confirmation not idempotent'; end if;
end $$;
rollback;
