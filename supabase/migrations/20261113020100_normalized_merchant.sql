alter table public.import_items add column normalized_merchant text;
alter table public.transactions add column normalized_merchant text;

create or replace function private.categorize_import_item() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_format text; v_result record;
begin
 select format into v_format from public.import_batches where id=new.batch_id and user_id=new.user_id;
 if v_format='cashradar_csv_v1' then new.categorization_source:='manual'; return new; end if;
 -- The ACBA merchant is a dedicated column; other parsers retain the entire raw description.
 new.merchant_name:=left(nullif(btrim(coalesce(new.raw_data->>'AD',new.raw_description,'')),''),500);
 if coalesce(new.raw_data->>'mcc','') ~ '^[0-9]{4}$' then new.mcc:=new.raw_data->>'mcc'; end if;
 select * into v_result from private.evaluate_category(new.user_id,new.transaction_type,new.merchant_name,new.mcc,new.category_id);
 new.category_id:=v_result.category_id; new.categorization_source:=v_result.source; new.normalized_merchant:=nullif(v_result.normalized_merchant,'');
 return new;
end;
$$;

create or replace function public.confirm_statement_import(p_batch_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_batch public.import_batches%rowtype; v_count integer; v_fees integer; v_skipped integer;
begin
 select * into v_batch from public.import_batches where id=p_batch_id and user_id=(select auth.uid()) for update;
 if not found then raise exception 'Import not found' using errcode='42501'; end if;
 if v_batch.status='completed' then return jsonb_build_object('imported_count',v_batch.imported_count,'duplicate_count',v_batch.duplicate_count,'already_confirmed',true); end if;
 if v_batch.status<>'ready' or v_batch.row_count<1 or v_batch.error_count<>0 then raise exception 'Import is not ready' using errcode='22023'; end if;
 perform 1 from public.accounts where id=v_batch.account_id and user_id=v_batch.user_id and currency=v_batch.account_currency and is_active for update;
 if not found then raise exception 'Account unavailable or currency changed' using errcode='22023'; end if;
 if exists(select 1 from public.import_item_details d join public.import_items i on i.id=d.id where i.batch_id=v_batch.id and i.user_id=v_batch.user_id
   and ((d.candidate_count>0 and (d.duplicate_decision is null or d.duplicate_signature is distinct from d.candidate_signature))
        or (d.candidate_count=0 and d.duplicate_decision is not null))) then
   raise exception 'Potential duplicates require review' using errcode='22023';
 end if;
 insert into public.deduplication_decisions(user_id,batch_id,item_id,decision,candidate_count)
 select i.user_id,i.batch_id,i.id,i.duplicate_decision,d.candidate_count from public.import_items i
 join public.import_item_details d on d.id=i.id where i.batch_id=v_batch.id and i.user_id=v_batch.user_id and d.candidate_count>0;
 select count(*) into v_skipped from public.import_items where batch_id=v_batch.id and user_id=v_batch.user_id and duplicate_decision='skip';
 insert into public.transactions(user_id,account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description,source,status,import_batch_id,merchant_name,mcc,categorization_source,normalized_merchant)
 select i.user_id,v_batch.account_id,i.category_id,i.transaction_type,i.transaction_date,i.amount,i.currency,i.account_amount,v_batch.account_currency,i.raw_description,'statement','confirmed',v_batch.id,i.merchant_name,i.mcc,i.categorization_source,i.normalized_merchant
 from public.import_items i where i.batch_id=v_batch.id and i.user_id=v_batch.user_id and i.duplicate_decision is distinct from 'skip' order by i.row_number;
 get diagnostics v_count=row_count;
 if v_count <> v_batch.row_count-v_skipped then raise exception 'Import row count mismatch' using errcode='22023'; end if;
 insert into public.transactions(user_id,account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description,source,status,import_batch_id)
 select i.user_id,v_batch.account_id,i.commission_category_id,'expense',i.transaction_date,i.commission_amount,v_batch.account_currency,i.commission_amount,v_batch.account_currency,
   left('Комиссия: ' || coalesce(i.raw_description,''),500),'statement','confirmed',v_batch.id
 from public.import_items i where i.batch_id=v_batch.id and i.user_id=v_batch.user_id and i.commission_amount is not null and i.duplicate_decision is distinct from 'skip' order by i.row_number;
 get diagnostics v_fees=row_count; v_count:=v_count+v_fees;
 update public.import_batches set status='completed',imported_count=v_count,duplicate_count=v_skipped,confirmed_at=now() where id=v_batch.id;
 return jsonb_build_object('imported_count',v_count,'duplicate_count',v_skipped,'already_confirmed',false);
end;
$$;
