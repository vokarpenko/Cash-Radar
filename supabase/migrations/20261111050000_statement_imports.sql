-- Originals are private; only the authenticated server function uploads them.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('statements', 'statements', false, 1048576, array['text/csv']);
create policy statement_objects_read_own on storage.objects for select to authenticated
  using (bucket_id = 'statements' and (storage.foldername(name))[1] = (select auth.uid())::text);

alter table public.accounts add constraint accounts_owner_id_unique unique (user_id, id);
create table public.import_batches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null,
  account_currency text not null check (account_currency ~ '^[A-Z]{3}$'),
  bank_id uuid references public.banks(id),
  original_filename text not null check (length(original_filename) between 1 and 160),
  object_path text not null unique,
  file_sha256 text not null check (file_sha256 ~ '^[0-9a-f]{64}$'),
  format text not null check (format = 'cashradar_csv_v1'),
  source text not null default 'statement' check (source = 'statement'),
  status text not null check (status in ('ready','invalid','completed')),
  row_count integer not null check (row_count between 0 and 500),
  error_count integer not null check (error_count between 0 and 5000),
  errors jsonb not null default '[]'::jsonb check (jsonb_typeof(errors) = 'array' and jsonb_array_length(errors) <= 100),
  imported_count integer not null default 0 check (imported_count between 0 and 500),
  period_start date,
  period_end date,
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  constraint import_batches_owner_id_unique unique (user_id, id),
  constraint import_batches_owner_file_unique unique (user_id, file_sha256),
  constraint import_batches_account_owner_fk foreign key (user_id, account_id) references public.accounts(user_id, id),
  constraint import_batch_object_path check (object_path = user_id::text || '/' || file_sha256 || '.csv'),
  constraint import_batch_period check (period_start is null or period_end is null or period_start <= period_end)
);
create index import_batches_owner_created_idx on public.import_batches(user_id, created_at desc);

create table public.import_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  batch_id uuid not null,
  row_number integer not null check (row_number between 2 and 501),
  transaction_date date not null check (transaction_date between date '1900-01-01' and date '2100-12-31'),
  transaction_type text not null check (transaction_type in ('income','expense')),
  amount numeric not null check (amount > 0 and amount < 1000000000000000000 and amount = trunc(amount, 2)),
  currency text not null check (currency in ('AMD','RUB','USD','EUR')),
  account_amount numeric not null check (account_amount > 0 and account_amount < 1000000000000000000 and account_amount = trunc(account_amount, 2)),
  category_id uuid not null,
  raw_description text check (raw_description is null or length(btrim(raw_description)) between 1 and 500),
  raw_data jsonb not null check (jsonb_typeof(raw_data) = 'object'),
  constraint import_items_batch_owner_fk foreign key (user_id, batch_id) references public.import_batches(user_id, id) on delete cascade,
  constraint import_items_category_owner_kind_fk foreign key (user_id, category_id, transaction_type) references public.categories(user_id, id, kind),
  constraint import_items_row_unique unique (batch_id, row_number)
);
create index import_items_owner_batch_idx on public.import_items(user_id, batch_id, row_number);

alter table public.import_batches enable row level security;
alter table public.import_items enable row level security;
revoke all on public.import_batches, public.import_items from public, anon, authenticated;
grant select on public.import_batches, public.import_items to authenticated;
grant all on public.import_batches, public.import_items to service_role;
create policy import_batches_read_own on public.import_batches for select to authenticated using ((select auth.uid()) = user_id);
create policy import_items_read_own on public.import_items for select to authenticated using ((select auth.uid()) = user_id);

alter table public.transactions drop constraint transactions_source_check;
alter table public.transactions add constraint transactions_source_check check (source in ('manual','statement'));
alter table public.transactions add column import_batch_id uuid;
alter table public.transactions add constraint transactions_import_batch_owner_fk
  foreign key (user_id, import_batch_id) references public.import_batches(user_id, id);
alter table public.transactions add constraint transactions_source_batch_consistent
  check ((source = 'manual' and import_batch_id is null) or (source = 'statement' and import_batch_id is not null));

-- Callable by the trusted server function only, never by browser clients.
create function public.register_statement_import(
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
  on conflict (user_id, file_sha256) do nothing returning id into v_batch;
  if v_batch is null then
    select * into v_existing from public.import_batches where user_id = p_user_id and file_sha256 = p_sha256;
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
revoke all on function public.register_statement_import(uuid, uuid, text, text, text, jsonb, jsonb, integer) from public, anon, authenticated;
grant execute on function public.register_statement_import(uuid, uuid, text, text, text, jsonb, jsonb, integer) to service_role;

-- One database transaction and a row lock make concurrent/repeated confirmations idempotent.
create function public.confirm_statement_import(p_batch_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_batch public.import_batches%rowtype; v_count integer;
begin
  select * into v_batch from public.import_batches where id = p_batch_id and user_id = (select auth.uid()) for update;
  if not found then raise exception 'Import not found' using errcode = '42501'; end if;
  if v_batch.status = 'completed' then return jsonb_build_object('imported_count', v_batch.imported_count, 'already_confirmed', true); end if;
  if v_batch.status <> 'ready' or v_batch.row_count < 1 or v_batch.error_count <> 0 then raise exception 'Import is not ready' using errcode = '22023'; end if;
  if not exists(select 1 from public.accounts where id = v_batch.account_id and user_id = v_batch.user_id and currency = v_batch.account_currency and is_active) then
    raise exception 'Account unavailable or currency changed' using errcode = '22023';
  end if;
  insert into public.transactions(user_id,account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description,source,status,import_batch_id)
  select i.user_id,v_batch.account_id,i.category_id,i.transaction_type,i.transaction_date,i.amount,i.currency,i.account_amount,v_batch.account_currency,i.raw_description,'statement','confirmed',v_batch.id
  from public.import_items i where i.batch_id = v_batch.id and i.user_id = v_batch.user_id order by i.row_number;
  get diagnostics v_count = row_count;
  if v_count <> v_batch.row_count then raise exception 'Import row count mismatch' using errcode = '22023'; end if;
  update public.import_batches set status = 'completed', imported_count = v_count, confirmed_at = now() where id = v_batch.id;
  return jsonb_build_object('imported_count', v_count, 'already_confirmed', false);
end;
$$;
revoke all on function public.confirm_statement_import(uuid) from public, anon, authenticated;
grant execute on function public.confirm_statement_import(uuid) to authenticated;
