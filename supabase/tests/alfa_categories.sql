\set ON_ERROR_STOP on
begin;
insert into auth.users (id,email,aud,role) values ('82000000-0000-4000-8000-000000000001','alfa-category@example.test','authenticated','authenticated');
insert into public.accounts (id,user_id,name,account_type,currency,initial_balance,bank_id) values
 ('82000000-0000-4000-8000-000000000002','82000000-0000-4000-8000-000000000001','Alfa','bank','RUB',0,(select id from public.banks where code='alfa_ru'));
insert into public.category_rules (user_id,kind,match_type,pattern,category_id)
select '82000000-0000-4000-8000-000000000001','expense','merchant_contains','custom merchant',id from public.categories where user_id='82000000-0000-4000-8000-000000000001' and name='Такси';
insert into public.category_rules (user_id,kind,match_type,pattern,category_id)
select '82000000-0000-4000-8000-000000000001','expense','mcc','5411',id from public.categories where user_id='82000000-0000-4000-8000-000000000001' and name='Продукты';
insert into public.category_feedback (user_id,kind,merchant_key,category_id)
select '82000000-0000-4000-8000-000000000001','expense',public.normalize_merchant('Known correction'),id from public.categories where user_id='82000000-0000-4000-8000-000000000001' and name='Такси';
delete from public.categories where user_id='82000000-0000-4000-8000-000000000001' and name='Путешествия';
select set_config('test.alfa.category.batch', (public.register_statement_import(
 '82000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000002','RUB','synthetic.xlsx',repeat('e',64),
 (select jsonb_agg(jsonb_build_object('row_number',n+20,'transaction_date','2026-11-01','transaction_type',kind,'amount',n::text,'currency','RUB','account_amount',n::text,
  'category_id',(select id from public.categories where user_id='82000000-0000-4000-8000-000000000001' and name=case when kind='income' then 'Прочие доходы' else 'Прочие расходы' end order by parent_id nulls first,id limit 1),
  'raw_description',descr,'raw_data',jsonb_build_object('posting_date','2026-11-02','bank_operation_code','SYNTH','E',bank,'mcc',mcc)))
  from (values
   (1,'expense','Коммунальные платежи','Synthetic utilities',null),
   (2,'expense','Супермаркеты','Synthetic groceries',null),
   (3,'expense','Кафе и рестораны','Synthetic cafe',null),
   (4,'expense','ЖКХ, налоги и штрафы','Synthetic ambiguous',null),
   (5,'expense','Прочие операции','Synthetic other',null),
   (6,'expense','Переводы','Synthetic transfer',null),
   (7,'expense','Супермаркеты','Custom merchant',null),
   (8,'expense','Кафе и рестораны','Synthetic MCC','5411'),
   (9,'income','Коммунальные платежи','Synthetic refund',null),
   (10,'expense','  ФАСТФУД  ','Synthetic fast food',null),
   (11,'expense','НЕИЗВЕСТНАЯ','Synthetic unknown',null),
   (12,'expense','Супермаркеты','Known correction',null),
   (13,'expense','Отели','Synthetic missing category',null)
  ) as v(n,kind,bank,descr,mcc)), '[]'::jsonb,0,'alfa_xlsx_v1')->>'id'),true);
select set_config('request.jwt.claims','{"sub":"82000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare r record; begin
 for r in select * from (values
  (1,'Коммунальные услуги','bank'),(2,'Продукты','bank'),(3,'Рестораны','bank'),
  (4,'Прочие расходы','fallback'),(5,'Прочие расходы','fallback'),(6,'Прочие расходы','fallback'),
  (7,'Такси','rule'),(8,'Продукты','mcc'),(9,'Прочие доходы','fallback'),
  (10,'Рестораны','bank'),(11,'Прочие расходы','fallback'),(12,'Такси','history'),(13,'Прочие расходы','fallback')) as e(n,name,source)
 loop
  if not exists(select 1 from public.import_item_details where batch_id=current_setting('test.alfa.category.batch')::uuid and row_number=r.n+20 and category_name=r.name and categorization_source=r.source) then
   raise exception 'Wrong category or priority on row %',r.n;
  end if;
 end loop;
 perform public.confirm_statement_import(current_setting('test.alfa.category.batch')::uuid);
 if (select count(*) from public.transaction_details where categorization_source='bank')<>4 then raise exception 'Bank category source not preserved'; end if;
end $$;
rollback;
