-- Allow the UI and transaction history to distinguish a bank hint from a user rule.
alter table public.import_items drop constraint import_items_categorization_source_check;
alter table public.import_items add constraint import_items_categorization_source_check check(categorization_source in ('manual','rule','alias','mcc','history','fallback','ai','delivery','bank'));
alter table public.transactions drop constraint transactions_categorization_source_check;
alter table public.transactions add constraint transactions_categorization_source_check check(categorization_source in ('manual','rule','alias','mcc','history','fallback','ai','delivery','bank'));

create or replace function private.categorize_import_item() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_format text; v_result record; v_default uuid; v_bank_category text; v_bank_target uuid;
begin
 select format into v_format from public.import_batches where id=new.batch_id and user_id=new.user_id;
 if v_format='alfa_xlsx_v1' then
  new.posting_date:=nullif(new.raw_data->>'posting_date','')::date;
  new.bank_operation_code:=nullif(btrim(new.raw_data->>'bank_operation_code'),'');
  new.original_amount_known:=false;
  if new.posting_date is null or new.bank_operation_code is null then raise exception 'Missing Alfa posting data' using errcode='22023'; end if;
 end if;
 if v_format='cashradar_csv_v1' then new.categorization_source:='manual'; return new; end if;
 new.merchant_name:=left(nullif(btrim(coalesce(new.raw_data->>'AD',new.raw_description,'')),''),500);
 if coalesce(new.raw_data->>'mcc','') ~ '^[0-9]{4}$' then new.mcc:=new.raw_data->>'mcc'; end if;
 v_default:=new.category_id;
 -- On reevaluation, start from the ordinary fallback, not a previously
 -- inferred bank category. This lets new rules and corrections take priority.
 if v_format='alfa_xlsx_v1' then
  select c.id into v_default from public.categories c where c.user_id=new.user_id and c.kind=new.transaction_type
   and c.name=case when new.transaction_type='income' then 'Прочие доходы' else 'Прочие расходы' end order by c.parent_id nulls first,c.id limit 1;
  v_default:=coalesce(v_default,new.category_id);
 end if;
 if tg_op='UPDATE' and old.categorization_source='ai' then
  select c.id into v_default from public.categories c where c.user_id=new.user_id and c.kind=new.transaction_type
   and c.name=case when new.transaction_type='income' then 'Прочие доходы' else 'Прочие расходы' end order by c.parent_id nulls first,c.id limit 1;
  v_default:=coalesce(v_default,new.category_id);
 end if;
 select * into v_result from private.evaluate_category(new.user_id,new.transaction_type,new.merchant_name,new.mcc,v_default);
 if v_format='alfa_xlsx_v1' and new.transaction_type='expense' and v_result.source='fallback' then
  v_bank_category:=case lower(regexp_replace(btrim(coalesce(new.raw_data->>'E','')), '\s+', ' ', 'g'))
   when 'супермаркеты' then 'Продукты'
   when 'кафе и рестораны' then 'Рестораны'
   when 'фастфуд' then 'Рестораны'
   when 'маркетплейсы' then 'Покупки'
   when 'азс' then 'Автомобиль'
   when 'такси' then 'Такси'
   when 'транспорт' then 'Транспорт'
   when 'авто' then 'Автомобиль'
   when 'путешествия' then 'Путешествия'
   when 'авиабилеты' then 'Путешествия'
   when 'ж/д билеты' then 'Путешествия'
   when 'отели' then 'Путешествия'
   when 'аптеки' then 'Здоровье'
   when 'здоровье' then 'Здоровье'
   when 'косметика' then 'Покупки'
   when 'дом и ремонт' then 'Покупки'
   when 'техника и электроника' then 'Покупки'
   when 'одежда и обувь' then 'Покупки'
   when 'ювелирные изделия' then 'Покупки'
   when 'цветы' then 'Покупки'
   when 'детские товары' then 'Покупки'
   when 'книги и канцтовары' then 'Покупки'
   when 'цифровые товары' then 'Покупки'
   when 'развлечения' then 'Развлечения'
   when 'связь и интернет' then 'Связь'
   when 'коммунальные платежи' then 'Коммунальные услуги'
   else null end;
  if v_bank_category is not null then
   select c.id into v_bank_target from public.categories c
    where c.user_id=new.user_id and c.kind='expense' and c.name=v_bank_category order by c.parent_id nulls first,c.id limit 1;
   if v_bank_target is not null then v_result.category_id:=v_bank_target; v_result.source:='bank'; end if;
  end if;
 end if;
 new.category_id:=v_result.category_id; new.categorization_source:=v_result.source; new.normalized_merchant:=nullif(v_result.normalized_merchant,'');
 return new;
end;
$$;
