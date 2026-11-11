-- Permit private XLSX originals while retaining existing CSV records and RPC compatibility.
update storage.buckets set allowed_mime_types = array['text/csv', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'] where id = 'statements';
alter table public.import_batches drop constraint import_batches_format_check;
alter table public.import_batches add constraint import_batches_format_check check (format in ('cashradar_csv_v1','ameria_xlsx_v1'));
alter table public.import_batches drop constraint import_batch_object_path;
alter table public.import_batches add constraint import_batch_object_path check (object_path = user_id::text || '/' || file_sha256 || case when format = 'ameria_xlsx_v1' then '.xlsx' else '.csv' end);

create or replace function public.register_statement_import(
  p_user_id uuid, p_account_id uuid, p_currency text, p_filename text,
  p_sha256 text, p_items jsonb, p_errors jsonb, p_error_count integer, p_format text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_batch uuid; v_existing public.import_batches%rowtype; v_account public.accounts%rowtype;
begin
  if p_format not in ('cashradar_csv_v1', 'ameria_xlsx_v1') or p_user_id is null or p_account_id is null or p_sha256 !~ '^[0-9a-f]{64}$' or
     jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 500 or
     jsonb_typeof(p_errors) <> 'array' or jsonb_array_length(p_errors) > 100 or
     p_error_count < jsonb_array_length(p_errors) or p_error_count > 5000 then
    raise exception 'Invalid import payload' using errcode = '22023';
  end if;
  select * into v_account from public.accounts where user_id = p_user_id and id = p_account_id and is_active;
  if not found or v_account.currency <> p_currency then raise exception 'Account unavailable or currency changed' using errcode = '22023'; end if;
  if p_format = 'ameria_xlsx_v1' and not exists(select 1 from public.banks where id = v_account.bank_id and code = 'ameria_am') then raise exception 'Ameria account required' using errcode = '22023'; end if;
  insert into public.import_batches(user_id, account_id, account_currency, bank_id, original_filename, object_path, file_sha256, format, status, row_count, error_count, errors)
  values (p_user_id, p_account_id, p_currency, v_account.bank_id, p_filename, p_user_id::text || '/' || p_sha256 || case when p_format = 'ameria_xlsx_v1' then '.xlsx' else '.csv' end, p_sha256,
    p_format, case when p_error_count = 0 and jsonb_array_length(p_items) > 0 then 'ready' else 'invalid' end,
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


revoke all on function public.register_statement_import(uuid, uuid, text, text, text, jsonb, jsonb, integer, text) from public, anon, authenticated;
grant execute on function public.register_statement_import(uuid, uuid, text, text, text, jsonb, jsonb, integer, text) to service_role;
