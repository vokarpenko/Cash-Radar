-- Invalid files may be retried; ready/completed copies remain unique per owner.
alter table public.import_batches drop constraint import_batches_owner_file_unique;
alter table public.import_batches drop constraint import_batches_object_path_key;
create unique index import_batches_owner_active_file_unique on public.import_batches(user_id, file_sha256) where status in ('ready','completed');

create or replace function public.register_statement_import(
  p_user_id uuid, p_account_id uuid, p_currency text, p_filename text,
  p_sha256 text, p_items jsonb, p_errors jsonb, p_error_count integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_batch uuid; v_existing public.import_batches%rowtype; v_account public.accounts%rowtype;
begin
  if p_user_id is null or p_account_id is null or p_sha256 !~ '^[0-9a-f]{64}$' or
     jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 500 or
     jsonb_typeof(p_errors) <> 'array' or jsonb_array_length(p_errors) > 100 or
     p_error_count < jsonb_array_length(p_errors) or p_error_count > 5000 then
    raise exception 'Invalid import payload' using errcode = '22023';
  end if;
  select * into v_account from public.accounts where user_id = p_user_id and id = p_account_id and is_active;
  if not found or v_account.currency <> p_currency then raise exception 'Account unavailable or currency changed' using errcode = '22023'; end if;
  insert into public.import_batches(user_id, account_id, account_currency, bank_id, original_filename, object_path, file_sha256, format, status, row_count, error_count, errors)
  values (p_user_id, p_account_id, p_currency, v_account.bank_id, p_filename, p_user_id::text || '/' || p_sha256 || '.csv', p_sha256,
    'cashradar_csv_v1', case when p_error_count = 0 and jsonb_array_length(p_items) > 0 then 'ready' else 'invalid' end,
    jsonb_array_length(p_items), p_error_count, p_errors)
  on conflict (user_id, file_sha256) where status in ('ready','completed') do nothing returning id into v_batch;
  if v_batch is null then
    select * into v_existing from public.import_batches where user_id = p_user_id and file_sha256 = p_sha256 and status in ('ready','completed');
    return jsonb_build_object('id', v_existing.id, 'status', v_existing.status, 'duplicate', true);
  end if;
  insert into public.import_items(user_id,batch_id,row_number,transaction_date,transaction_type,amount,currency,account_amount,category_id,raw_description,raw_data)
  select p_user_id,v_batch,x.row_number,x.transaction_date,x.transaction_type,x.amount,x.currency,x.account_amount,x.category_id,x.raw_description,x.raw_data
  from jsonb_to_recordset(p_items) as x(row_number integer, transaction_date date, transaction_type text, amount numeric, currency text, account_amount numeric, category_id uuid, raw_description text, raw_data jsonb);
  if exists(select 1 from public.import_items where batch_id = v_batch and currency = p_currency and amount <> account_amount) then
    raise exception 'Amounts differ for same currency' using errcode = '22023';
  end if;
  update public.import_batches set period_start = (select min(transaction_date) from public.import_items where batch_id = v_batch),
    period_end = (select max(transaction_date) from public.import_items where batch_id = v_batch) where id = v_batch;
  return jsonb_build_object('id', v_batch, 'status', case when p_error_count = 0 and jsonb_array_length(p_items) > 0 then 'ready' else 'invalid' end, 'duplicate', false);
end;
$$;

create or replace function public.confirm_statement_import(p_batch_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_batch public.import_batches%rowtype; v_count integer;
begin
  select * into v_batch from public.import_batches where id = p_batch_id and user_id = (select auth.uid()) for update;
  if not found then raise exception 'Import not found' using errcode = '42501'; end if;
  if v_batch.status = 'completed' then return jsonb_build_object('imported_count', v_batch.imported_count, 'already_confirmed', true); end if;
  if v_batch.status <> 'ready' or v_batch.row_count < 1 or v_batch.error_count <> 0 then raise exception 'Import is not ready' using errcode = '22023'; end if;
  perform 1 from public.accounts where id = v_batch.account_id and user_id = v_batch.user_id and currency = v_batch.account_currency and is_active for update;
  if not found then raise exception 'Account unavailable or currency changed' using errcode = '22023'; end if;
  insert into public.transactions(user_id,account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description,source,status,import_batch_id)
  select i.user_id,v_batch.account_id,i.category_id,i.transaction_type,i.transaction_date,i.amount,i.currency,i.account_amount,v_batch.account_currency,i.raw_description,'statement','confirmed',v_batch.id
  from public.import_items i where i.batch_id = v_batch.id and i.user_id = v_batch.user_id order by i.row_number;
  get diagnostics v_count = row_count;
  if v_count <> v_batch.row_count then raise exception 'Import row count mismatch' using errcode = '22023'; end if;
  update public.import_batches set status = 'completed', imported_count = v_count, confirmed_at = now() where id = v_batch.id;
  return jsonb_build_object('imported_count', v_count, 'already_confirmed', false);
end;
$$;
