\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role) values
 ('fb000000-0000-4000-8000-000000000001','repeat-a@example.test','authenticated','authenticated'),
 ('fb000000-0000-4000-8000-000000000002','repeat-b@example.test','authenticated','authenticated');
insert into public.accounts(id,user_id,name,account_type,bank_id,currency,initial_balance)
select 'fb000000-0000-4000-8000-000000000003','fb000000-0000-4000-8000-000000000001','Account','bank',id,'RUB',0
from public.banks where code='alfa_ru';
select set_config('test.category',(select id::text from public.categories where user_id='fb000000-0000-4000-8000-000000000001' and name='Прочие расходы'),true);
select set_config('test.items',jsonb_build_array(jsonb_build_object(
 'row_number',2,'transaction_date','2026-11-01','transaction_type','expense','amount','12',
 'currency','RUB','account_amount','12','category_id',current_setting('test.category'),
 'raw_description','Synthetic merchant','raw_data',jsonb_build_object('posting_date','2026-11-01','bank_operation_code','SYNTHETIC')))::text,true);
select set_config('test.batch',(public.register_statement_import('fb000000-0000-4000-8000-000000000001','fb000000-0000-4000-8000-000000000003','RUB','synthetic.xlsx',repeat('a',64),current_setting('test.items')::jsonb,'[]',0,'alfa_xlsx_v1')->>'id'),true);
select set_config('request.jwt.claims','{"sub":"fb000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select public.confirm_statement_import(current_setting('test.batch')::uuid);
select set_config('test.retry',public.repeat_statement_import(current_setting('test.batch')::uuid)::text,true);
do $$ begin
 if not exists(select 1 from public.import_batches where id=current_setting('test.batch')::uuid and status='superseded') then raise exception 'Original history lost'; end if;
 if not exists(select 1 from public.import_item_details where batch_id=current_setting('test.retry')::uuid and candidate_count=1) then raise exception 'Existing transaction not suggested as duplicate'; end if;
 if (select count(*) from public.transactions where import_batch_id=current_setting('test.batch')::uuid)<>1 then raise exception 'Original transaction changed'; end if;
 begin perform public.repeat_statement_import(current_setting('test.batch')::uuid); raise exception 'Repeated original allowed'; exception when invalid_parameter_value then null; end;
end $$;
reset role;
delete from public.transactions where import_batch_id=current_setting('test.batch')::uuid;
set local role authenticated;
do $$ begin
 if exists(select 1 from public.import_item_details where batch_id=current_setting('test.retry')::uuid and candidate_count<>0) then raise exception 'Deleted operation remains a duplicate'; end if;
end $$;
select public.confirm_statement_import(current_setting('test.retry')::uuid);
do $$ begin
 if (select count(*) from public.transactions where import_batch_id=current_setting('test.retry')::uuid)<>1 then raise exception 'Deleted operation not restored'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"fb000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.repeat_statement_import(current_setting('test.retry')::uuid); raise exception 'Foreign import allowed'; exception when insufficient_privilege then null; end;
end $$;
rollback;
