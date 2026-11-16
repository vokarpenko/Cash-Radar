-- Import Alfa account statements without inventing original purchase currency or amount.
alter table public.import_batches drop constraint import_batches_format_check;
alter table public.import_batches add constraint import_batches_format_check check (format in ('cashradar_csv_v1','ameria_xlsx_v1','acba_xlsx_v1','alfa_xlsx_v1'));
alter table public.import_batches drop constraint import_batch_object_path;
alter table public.import_batches add constraint import_batch_object_path check (object_path = user_id::text || '/' || file_sha256 || case when format in ('ameria_xlsx_v1','acba_xlsx_v1','alfa_xlsx_v1') then '.xlsx' else '.csv' end);
alter table public.import_items add column posting_date date, add column bank_operation_code text, add column original_amount_known boolean not null default true;
alter table public.transactions add column posting_date date, add column bank_operation_code text, add column original_amount_known boolean not null default true;

create or replace function private.categorize_import_item() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_format text; v_result record; v_default uuid;
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
 if tg_op='UPDATE' and old.categorization_source='ai' then
  select c.id into v_default from public.categories c where c.user_id=new.user_id and c.kind=new.transaction_type
   and c.name=case when new.transaction_type='income' then 'Прочие доходы' else 'Прочие расходы' end order by c.id limit 1;
  v_default:=coalesce(v_default,new.category_id);
 end if;
 select * into v_result from private.evaluate_category(new.user_id,new.transaction_type,new.merchant_name,new.mcc,v_default);
 new.category_id:=v_result.category_id; new.categorization_source:=v_result.source; new.normalized_merchant:=nullif(v_result.normalized_merchant,'');
 return new;
end;
$$;

create or replace function public.register_statement_import(
  p_user_id uuid, p_account_id uuid, p_currency text, p_filename text,
  p_sha256 text, p_items jsonb, p_errors jsonb, p_error_count integer, p_format text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_batch uuid; v_existing public.import_batches%rowtype; v_account public.accounts%rowtype;
begin
  if p_format not in ('cashradar_csv_v1', 'ameria_xlsx_v1', 'acba_xlsx_v1', 'alfa_xlsx_v1') or p_user_id is null or p_account_id is null or p_sha256 !~ '^[0-9a-f]{64}$' or
     jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 500 or
     jsonb_typeof(p_errors) <> 'array' or jsonb_array_length(p_errors) > 100 or
     p_error_count < jsonb_array_length(p_errors) or p_error_count > 5000 then
    raise exception 'Invalid import payload' using errcode = '22023';
  end if;
  select * into v_account from public.accounts where user_id = p_user_id and id = p_account_id and is_active;
  if not found or v_account.currency <> p_currency then raise exception 'Account unavailable or currency changed' using errcode = '22023'; end if;
  if p_format = 'ameria_xlsx_v1' and not exists(select 1 from public.banks where id = v_account.bank_id and code = 'ameria_am') then raise exception 'Ameria account required' using errcode = '22023'; end if;
  if p_format = 'acba_xlsx_v1' and not exists(select 1 from public.banks where id = v_account.bank_id and code = 'acba_am') then raise exception 'ACBA account required' using errcode = '22023'; end if;
  if p_format = 'alfa_xlsx_v1' and not exists(select 1 from public.banks where id = v_account.bank_id and code = 'alfa_ru') then raise exception 'Alfa account required' using errcode = '22023'; end if;
  insert into public.import_batches(user_id, account_id, account_currency, bank_id, original_filename, object_path, file_sha256, format, status, row_count, error_count, errors)
  values (p_user_id, p_account_id, p_currency, v_account.bank_id, p_filename, p_user_id::text || '/' || p_sha256 || case when p_format in ('ameria_xlsx_v1','acba_xlsx_v1','alfa_xlsx_v1') then '.xlsx' else '.csv' end, p_sha256,
    p_format, case when p_error_count = 0 and jsonb_array_length(p_items) > 0 then 'ready' else 'invalid' end,
    jsonb_array_length(p_items), p_error_count, p_errors)
  on conflict (user_id, file_sha256) where status in ('ready','completed') do nothing returning id into v_batch;
  if v_batch is null then
    select * into v_existing from public.import_batches where user_id = p_user_id and file_sha256 = p_sha256 and status in ('ready','completed');
    return jsonb_build_object('id', v_existing.id, 'status', v_existing.status, 'duplicate', true);
  end if;
  insert into public.import_items(user_id,batch_id,row_number,transaction_date,transaction_type,amount,currency,account_amount,category_id,raw_description,raw_data,commission_amount,commission_category_id)
  select p_user_id,v_batch,x.row_number,x.transaction_date,x.transaction_type,x.amount,x.currency,x.account_amount,x.category_id,x.raw_description,x.raw_data,x.commission_amount,x.commission_category_id
  from jsonb_to_recordset(p_items) as x(row_number integer, transaction_date date, transaction_type text, amount numeric, currency text, account_amount numeric, category_id uuid, raw_description text, raw_data jsonb, commission_amount numeric, commission_category_id uuid);
  if exists(select 1 from public.import_items i join public.categories c on c.id = i.commission_category_id and c.user_id = i.user_id where i.batch_id = v_batch and c.kind <> 'expense') then raise exception 'Invalid commission category' using errcode = '22023'; end if;
  if exists(select 1 from public.import_items where batch_id = v_batch and currency = p_currency and amount <> account_amount) then
    raise exception 'Amounts differ for same currency' using errcode = '22023';
  end if;
  update public.import_batches set period_start = (select min(transaction_date) from public.import_items where batch_id = v_batch),
    period_end = (select max(transaction_date) from public.import_items where batch_id = v_batch) where id = v_batch;
  return jsonb_build_object('id', v_batch, 'status', case when p_error_count = 0 and jsonb_array_length(p_items) > 0 then 'ready' else 'invalid' end, 'duplicate', false);
end;
$$;




create or replace view public.import_item_details with (security_invoker=true) as
select i.id, i.batch_id, i.row_number, i.transaction_date, i.transaction_type,
       i.amount::text as amount, i.currency, i.account_amount::text as account_amount,
       i.category_id, c.name as category_name, i.raw_description, i.commission_amount::text as commission_amount,
       i.duplicate_decision,
       (select count(*)::integer from public.import_duplicate_candidates d where d.item_id=i.id) as candidate_count,
       (select md5(string_agg(d.candidate_type || ':' || d.candidate_id::text || ':' || d.version, ',' order by d.candidate_type,d.candidate_id))
        from public.import_duplicate_candidates d where d.item_id=i.id) as candidate_signature,
       i.duplicate_signature, i.merchant_name, i.mcc, i.categorization_source, i.posting_date, i.bank_operation_code, i.original_amount_known
from public.import_items i join public.categories c on c.id=i.category_id and c.user_id=i.user_id;


create or replace view public.transaction_details with (security_invoker=true) as
select t.id,t.account_id,a.name as account_name,a.is_active as account_active,t.category_id,c.name as category_name,
 t.transaction_type,t.transaction_date,t.amount::text as amount,t.currency,t.account_amount::text as account_amount,
 t.account_currency,t.raw_description,t.source,t.status,t.created_at,t.merchant_name,t.mcc,t.categorization_source,
 (select g.id from public.transfer_groups g where g.user_id=t.user_id and t.id in(g.debit_id,g.credit_id) limit 1) as transfer_group_id,
 (select g.id from public.transfer_groups g where g.user_id=t.user_id and t.id=g.fee_id limit 1) as transfer_fee_group_id,
 t.updated_at::text as updated_at, t.posting_date, t.bank_operation_code, t.original_amount_known
from public.transactions t join public.accounts a on a.user_id=t.user_id and a.id=t.account_id
join public.categories c on c.user_id=t.user_id and c.id=t.category_id;


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
 insert into public.transactions(user_id,account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description,source,status,import_batch_id,merchant_name,mcc,categorization_source,normalized_merchant,posting_date,bank_operation_code,original_amount_known)
 select i.user_id,v_batch.account_id,i.category_id,i.transaction_type,i.transaction_date,i.amount,i.currency,i.account_amount,v_batch.account_currency,i.raw_description,'statement','confirmed',v_batch.id,i.merchant_name,i.mcc,i.categorization_source,i.normalized_merchant,i.posting_date,i.bank_operation_code,i.original_amount_known
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
