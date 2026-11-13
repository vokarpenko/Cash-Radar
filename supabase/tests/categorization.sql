\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role) values
 ('90000000-0000-4000-8000-000000000001','stage12-a@example.test','authenticated','authenticated'),
 ('90000000-0000-4000-8000-000000000002','stage12-b@example.test','authenticated','authenticated');
insert into public.accounts(id,user_id,name,account_type,bank_id,currency,initial_balance)
select '91000000-0000-4000-8000-000000000001','90000000-0000-4000-8000-000000000001','A','bank',id,'AMD',100 from public.banks where code='acba_am';
select set_config('test.default',(select id::text from public.categories where user_id='90000000-0000-4000-8000-000000000001' and name='Прочие расходы'),true),
 set_config('test.food',(select id::text from public.categories where user_id='90000000-0000-4000-8000-000000000001' and name='Рестораны'),true),
 set_config('test.taxi',(select id::text from public.categories where user_id='90000000-0000-4000-8000-000000000001' and name='Такси'),true),
 set_config('test.shopping',(select id::text from public.categories where user_id='90000000-0000-4000-8000-000000000001' and name='Покупки'),true);
select set_config('request.jwt.claims','{"sub":"90000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
insert into public.category_rules(kind,match_type,pattern,category_id,priority) values
 ('expense','merchant_contains','glovo',current_setting('test.food')::uuid,100),
 ('expense','merchant_contains','glovo',current_setting('test.taxi')::uuid,200),
 ('expense','merchant_exact','canonical cafe',current_setting('test.food')::uuid,100),
 ('expense','mcc','5812',current_setting('test.shopping')::uuid,100);
insert into public.merchant_aliases(kind,alias,canonical_name,category_id) values
 ('expense','delivery alias','canonical cafe',null),('expense','taxi alias','taxi canonical',current_setting('test.taxi')::uuid);
do $$ begin
 begin insert into public.category_feedback(user_id,kind,merchant_key,category_id) values ((select auth.uid()),'expense','forged',current_setting('test.food')::uuid); raise exception 'feedback spoofed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('test.data',jsonb_build_array(
 jsonb_build_object('row_number',2,'transaction_date','2026-11-01','transaction_type','expense','amount','10','currency','AMD','account_amount','10','category_id',current_setting('test.default'),'raw_description','Sale','raw_data',jsonb_build_object('AD','Glovo Pay','mcc','5812')),
 jsonb_build_object('row_number',3,'transaction_date','2026-11-02','transaction_type','expense','amount','11','currency','AMD','account_amount','11','category_id',current_setting('test.default'),'raw_description','Sale','raw_data',jsonb_build_object('AD','Delivery Alias')),
 jsonb_build_object('row_number',4,'transaction_date','2026-11-03','transaction_type','expense','amount','12','currency','AMD','account_amount','12','category_id',current_setting('test.default'),'raw_description','Sale','raw_data',jsonb_build_object('AD','Taxi Alias')),
 jsonb_build_object('row_number',5,'transaction_date','2026-11-04','transaction_type','expense','amount','13','currency','AMD','account_amount','13','category_id',current_setting('test.default'),'raw_description','Unknown','raw_data',jsonb_build_object('mcc','5812')),
 jsonb_build_object('row_number',6,'transaction_date','2026-11-05','transaction_type','expense','amount','14','currency','AMD','account_amount','14','category_id',current_setting('test.default'),'raw_description','Local Bakery','raw_data','{}'::jsonb)
)::text,true);
select set_config('test.batch',(public.register_statement_import('90000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','AMD','fixture.xlsx',repeat('8',64),current_setting('test.data')::jsonb,'[]',0,'acba_xlsx_v1')->>'id'),true);
do $$ begin
 if not exists(select 1 from public.import_items where batch_id=current_setting('test.batch')::uuid and row_number=2 and category_id=current_setting('test.taxi')::uuid and categorization_source='rule') then raise exception 'priority or rule precedence failed'; end if;
 if not exists(select 1 from public.import_items where batch_id=current_setting('test.batch')::uuid and row_number=3 and category_id=current_setting('test.food')::uuid and categorization_source='alias' and normalized_merchant='canonical cafe') then raise exception 'alias canonical matching failed'; end if;
 if not exists(select 1 from public.import_items where batch_id=current_setting('test.batch')::uuid and row_number=4 and category_id=current_setting('test.taxi')::uuid and categorization_source='alias') then raise exception 'alias category failed'; end if;
 if not exists(select 1 from public.import_items where batch_id=current_setting('test.batch')::uuid and row_number=5 and category_id=current_setting('test.shopping')::uuid and categorization_source='mcc') then raise exception 'MCC failed'; end if;
 if not exists(select 1 from public.import_items where batch_id=current_setting('test.batch')::uuid and row_number=6 and category_id=current_setting('test.default')::uuid and categorization_source='fallback') then raise exception 'fallback failed'; end if;
end $$;
set local role authenticated;
select public.confirm_statement_import(current_setting('test.batch')::uuid);
do $$ begin
 if not exists(select 1 from public.transactions where import_batch_id=current_setting('test.batch')::uuid and normalized_merchant='canonical cafe' and categorization_source='alias' and category_id=current_setting('test.food')::uuid) then raise exception 'category provenance or normalized merchant lost on confirmation'; end if;
end $$;
update public.transactions set category_id=current_setting('test.food')::uuid where import_batch_id=current_setting('test.batch')::uuid and raw_description='Local Bakery';
do $$ begin
 if not exists(select 1 from public.category_feedback where merchant_key='local bakery' and category_id=current_setting('test.food')::uuid) then raise exception 'manual correction was not learned'; end if;
 if not exists(select 1 from public.transaction_details where raw_description='Local Bakery' and categorization_source='manual') then raise exception 'manual provenance lost'; end if;
end $$;
reset role;
select set_config('test.batch2',(public.register_statement_import('90000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','AMD','fixture2.xlsx',repeat('9',64),jsonb_build_array(jsonb_build_object('row_number',2,'transaction_date','2026-11-06','transaction_type','expense','amount','20','currency','AMD','account_amount','20','category_id',current_setting('test.default'),'raw_description','Local Bakery','raw_data','{}'::jsonb)),'[]',0,'acba_xlsx_v1')->>'id'),true);
do $$ begin
 if not exists(select 1 from public.import_items where batch_id=current_setting('test.batch2')::uuid and category_id=current_setting('test.food')::uuid and categorization_source='history') then raise exception 'learned category not applied'; end if;
end $$;
set local role authenticated;
insert into public.category_rules(kind,match_type,pattern,category_id,priority) values('expense','merchant_contains','local bakery',current_setting('test.taxi')::uuid,500);
select public.reapply_import_categories(current_setting('test.batch2')::uuid);
do $$ begin
 if not exists(select 1 from public.import_items where batch_id=current_setting('test.batch2')::uuid and category_id=current_setting('test.taxi')::uuid and categorization_source='rule') then raise exception 'rules were not reapplied'; end if;
end $$;
reset role;
select set_config('test.csv',(public.register_statement_import('90000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','AMD','fixture.csv',repeat('7',64),jsonb_build_array(jsonb_build_object('row_number',2,'transaction_date','2026-11-06','transaction_type','expense','amount','21','currency','AMD','account_amount','21','category_id',current_setting('test.default'),'raw_description','Glovo Pay','raw_data','{}'::jsonb)),'[]',0,'cashradar_csv_v1')->>'id'),true);
set local role authenticated;
select public.reapply_import_categories(current_setting('test.csv')::uuid);
do $$ begin
 if not exists(select 1 from public.import_items where batch_id=current_setting('test.csv')::uuid and category_id=current_setting('test.default')::uuid and categorization_source='manual') then raise exception 'CSV explicit category overwritten'; end if;
end $$;
reset role;
set local role authenticated;
insert into public.merchant_aliases(kind,alias,canonical_name) values('expense','another alias','canonical cafe');
reset role;
select set_config('test.aliasbatch',(public.register_statement_import('90000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','AMD','alias.xlsx',repeat('6',64),jsonb_build_array(jsonb_build_object('row_number',2,'transaction_date','2026-11-03','transaction_type','expense','amount','11','currency','AMD','account_amount','11','category_id',current_setting('test.default'),'raw_description','Other source description','raw_data',jsonb_build_object('AD','Another Alias'))),'[]',0,'acba_xlsx_v1')->>'id'),true);
set local role authenticated;
do $$ begin
 if not exists(select 1 from public.import_item_details where batch_id=current_setting('test.aliasbatch')::uuid and candidate_count=1) then raise exception 'normalized aliases did not suggest a match'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"90000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.reapply_import_categories(current_setting('test.batch2')::uuid); raise exception 'foreign reapply allowed'; exception when insufficient_privilege then null; end;
 if exists(select 1 from public.category_rules) or exists(select 1 from public.merchant_aliases) or exists(select 1 from public.category_feedback) then raise exception 'foreign user sees category rules'; end if;
 begin insert into public.category_rules(kind,match_type,pattern,category_id) values('expense','merchant_contains','glovo',current_setting('test.food')::uuid); raise exception 'foreign category accepted'; exception when foreign_key_violation then null; end;
end $$;
reset role;
rollback;
