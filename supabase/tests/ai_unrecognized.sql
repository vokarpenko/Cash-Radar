\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role) values
 ('94000000-0000-4000-8000-000000000001','stage13-cache-a@example.test','authenticated','authenticated'),
 ('94000000-0000-4000-8000-000000000002','stage13-cache-b@example.test','authenticated','authenticated');
insert into public.accounts(id,user_id,name,account_type,bank_id,currency,initial_balance)
select '95000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001','A','bank',id,'AMD',0 from public.banks where code='acba_am';
select set_config('test.default',(select id::text from public.categories where user_id='94000000-0000-4000-8000-000000000001' and name='Прочие расходы'),true);
select set_config('test.data',jsonb_build_array(
 jsonb_build_object('row_number',2,'transaction_date','2026-11-01','transaction_type','expense','amount','10','currency','AMD','account_amount','10','category_id',current_setting('test.default'),'raw_description','Imaginary Unknown','raw_data','{}'::jsonb),
 jsonb_build_object('row_number',3,'transaction_date','2026-11-02','transaction_type','expense','amount','11','currency','AMD','account_amount','11','category_id',current_setting('test.default'),'raw_description','Imaginary Grocer','raw_data','{}'::jsonb),
 jsonb_build_object('row_number',4,'transaction_date','2026-11-03','transaction_type','expense','amount','12','currency','AMD','account_amount','12','category_id',current_setting('test.default'),'raw_description','Imaginary Vague','raw_data','{}'::jsonb)
)::text,true);
select set_config('test.batch',(public.register_statement_import('94000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000001','AMD','fixture.xlsx',repeat('4',64),current_setting('test.data')::jsonb,'[]',0,'acba_xlsx_v1')->>'id'),true);
select set_config('test.unknown',(select group_id from private.ai_candidates('94000000-0000-4000-8000-000000000001',current_setting('test.batch')::uuid) where merchant='Imaginary Unknown'),true),
 set_config('test.grocer',(select group_id from private.ai_candidates('94000000-0000-4000-8000-000000000001',current_setting('test.batch')::uuid) where merchant='Imaginary Grocer'),true),
 set_config('test.vague',(select group_id from private.ai_candidates('94000000-0000-4000-8000-000000000001',current_setting('test.batch')::uuid) where merchant='Imaginary Vague'),true);
select public.ai_reserve('94000000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000001');
select public.ai_store_results('94000000-0000-4000-8000-000000000001',current_setting('test.batch')::uuid,'96000000-0000-4000-8000-000000000001',jsonb_build_array(
 jsonb_build_object('groupId',current_setting('test.unknown'),'category','unknown','confidence',0.0,'unambiguous',false,'reason','unknown'),
 jsonb_build_object('groupId',current_setting('test.grocer'),'category','groceries','confidence',0.95,'unambiguous',true,'reason','clear'),
 jsonb_build_object('groupId',current_setting('test.vague'),'category','taxi','confidence',0.3,'unambiguous',false,'reason','ambiguous')),'gemini-3.8-flash');
do $$ begin
 if not exists(select 1 from public.ai_unrecognized_merchants where merchant_key='imaginary unknown' and model='gemini-3.8-flash') then raise exception 'unknown result was not saved'; end if;
 if not exists(select 1 from public.ai_unrecognized_merchants where merchant_key='imaginary vague') then raise exception 'low-confidence result was not saved'; end if;
 if not exists(select 1 from public.ai_merchant_rules where merchant_key='imaginary grocer' and model='gemini-3.8-flash') then raise exception 'actual fallback model not recorded'; end if;
 if exists(select 1 from private.ai_candidates('94000000-0000-4000-8000-000000000001',current_setting('test.batch')::uuid)) then raise exception 'unknown or recognized merchant would be resent'; end if;
end $$;
select set_config('test.batch2',(public.register_statement_import('94000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000001','AMD','fixture2.xlsx',repeat('5',64),current_setting('test.data')::jsonb,'[]',0,'acba_xlsx_v1')->>'id'),true);
do $$ begin
 if exists(select 1 from private.ai_candidates('94000000-0000-4000-8000-000000000001',current_setting('test.batch2')::uuid)) then raise exception 'future import sent known names'; end if;
 if not exists(select 1 from public.import_items where batch_id=current_setting('test.batch2')::uuid and merchant_name='Imaginary Grocer' and categorization_source='ai') then raise exception 'saved rule did not apply automatically'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.ai_unrecognized_merchants) then raise exception 'another user sees cached names'; end if;
 delete from public.ai_unrecognized_merchants where merchant_key='imaginary unknown';
 if found then raise exception 'another user deleted cached name'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
delete from public.ai_unrecognized_merchants where merchant_key='imaginary unknown';
do $$ begin
 if (select count(*) from public.ai_import_candidates(current_setting('test.batch2')::uuid))<>1 then raise exception 'owner could not allow retry'; end if;
end $$;
reset role;
rollback;
