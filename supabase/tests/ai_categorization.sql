\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role) values
 ('91000000-0000-4000-8000-000000000001','stage13-a@example.test','authenticated','authenticated'),
 ('91000000-0000-4000-8000-000000000002','stage13-b@example.test','authenticated','authenticated');
insert into public.accounts(id,user_id,name,account_type,bank_id,currency,initial_balance)
select '92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','A','bank',id,'AMD',100 from public.banks where code='acba_am';
select set_config('test.default',(select id::text from public.categories where user_id='91000000-0000-4000-8000-000000000001' and name='Прочие расходы'),true),
 set_config('test.food',(select id::text from public.categories where user_id='91000000-0000-4000-8000-000000000001' and name='Продукты'),true),
 set_config('test.taxi',(select id::text from public.categories where user_id='91000000-0000-4000-8000-000000000001' and name='Такси'),true);
select set_config('test.data',jsonb_build_array(
 jsonb_build_object('row_number',2,'transaction_date','2026-11-01','transaction_type','expense','amount','10','currency','AMD','account_amount','10','category_id',current_setting('test.default'),'raw_description','Imaginary Grocer','raw_data','{}'::jsonb),
 jsonb_build_object('row_number',3,'transaction_date','2026-11-02','transaction_type','expense','amount','11','currency','AMD','account_amount','11','category_id',current_setting('test.default'),'raw_description','Imaginary Grocer','raw_data','{}'::jsonb),
 jsonb_build_object('row_number',4,'transaction_date','2026-11-03','transaction_type','expense','amount','12','currency','AMD','account_amount','12','category_id',current_setting('test.default'),'raw_description','Imaginary Taxi','raw_data','{}'::jsonb)
)::text,true);
select set_config('test.batch',(public.register_statement_import('91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','AMD','fixture.xlsx',repeat('3',64),current_setting('test.data')::jsonb,'[]',0,'acba_xlsx_v1')->>'id'),true);
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if (select count(*) from public.ai_import_candidates(current_setting('test.batch')::uuid))<>2 then raise exception 'grouping failed'; end if;
 if not exists(select 1 from public.ai_import_candidates(current_setting('test.batch')::uuid) where merchant='Imaginary Grocer' and item_count=2) then raise exception 'group count failed'; end if;
 begin perform public.ai_reserve((select auth.uid()),gen_random_uuid()); raise exception 'reservation allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('test.group',(select group_id from private.ai_candidates('91000000-0000-4000-8000-000000000001',current_setting('test.batch')::uuid) where merchant='Imaginary Grocer'),true);
select set_config('test.medium',(select group_id from private.ai_candidates('91000000-0000-4000-8000-000000000001',current_setting('test.batch')::uuid) where merchant='Imaginary Taxi'),true);
do $$ begin
 if not public.ai_reserve('91000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001') then raise exception 'lock missing'; end if;
 if public.ai_reserve('91000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002') then raise exception 'concurrent request allowed'; end if;
end $$;
select public.ai_store_results('91000000-0000-4000-8000-000000000001',current_setting('test.batch')::uuid,'93000000-0000-4000-8000-000000000001',jsonb_build_array(
 jsonb_build_object('groupId',current_setting('test.group'),'category','groceries','confidence',0.95,'unambiguous',true,'reason','clear'),
 jsonb_build_object('groupId',current_setting('test.medium'),'category','taxi','confidence',0.7,'unambiguous',false,'reason','ambiguous')),'gemini-4-hydrogen');
do $$ begin
 if (select count(*) from public.import_items where batch_id=current_setting('test.batch')::uuid and category_id=current_setting('test.food')::uuid and categorization_source='ai')<>2 then raise exception 'AI mapping not applied'; end if;
 if (select count(*) from public.ai_merchant_rules where user_id='91000000-0000-4000-8000-000000000001')<>1 or (select count(*) from public.ai_suggestions where user_id='91000000-0000-4000-8000-000000000001')<>1 then raise exception 'result storage failed'; end if;
 if exists(select 1 from private.ai_candidates('91000000-0000-4000-8000-000000000001',current_setting('test.batch')::uuid)) then raise exception 'known rules or pending suggestions resent'; end if;
end $$;
set local role authenticated;
update public.ai_merchant_rules set enabled=false where merchant_key='imaginary grocer';
select public.reapply_import_categories(current_setting('test.batch')::uuid);
do $$ begin
 if (select count(*) from public.import_items where batch_id=current_setting('test.batch')::uuid and category_id=current_setting('test.default')::uuid and categorization_source='fallback' and raw_description='Imaginary Grocer')<>2 then raise exception 'disabled rule retained a stale category'; end if;
end $$;
update public.ai_merchant_rules set enabled=true where merchant_key='imaginary grocer';
select public.reapply_import_categories(current_setting('test.batch')::uuid);
reset role;
select public.ai_release('91000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001');
select set_config('test.suggestion',(select id::text from public.ai_suggestions where user_id='91000000-0000-4000-8000-000000000001' limit 1),true);
set local role authenticated;
select public.ai_review_suggestion(current_setting('test.suggestion')::uuid,true);
select public.reapply_import_categories(current_setting('test.batch')::uuid);
do $$ begin
 if not exists(select 1 from public.import_items where batch_id=current_setting('test.batch')::uuid and category_id=current_setting('test.taxi')::uuid and categorization_source='ai') then raise exception 'accepted suggestion not applied'; end if;
end $$;
select public.confirm_statement_import(current_setting('test.batch')::uuid);
update public.transactions set category_id=current_setting('test.taxi')::uuid where import_batch_id=current_setting('test.batch')::uuid and raw_description='Imaginary Grocer';
do $$ begin
 if exists(select 1 from public.ai_merchant_rules where merchant_key='imaginary grocer' and enabled) then raise exception 'conflicting AI rule remains enabled'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.ai_merchant_rules) or exists(select 1 from public.ai_suggestions) then raise exception 'foreign data visible'; end if;
 begin perform public.ai_import_candidates(current_setting('test.batch')::uuid); raise exception 'foreign batch visible'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
