-- Similarity is evidence for review, never proof that a payment is a duplicate.
create function public.normalize_merchant(p_value text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select pg_catalog.btrim(pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.btrim(coalesce(p_value,''))), '[[:space:][:punct:]]+', ' ', 'g'));
$$;
grant execute on function public.normalize_merchant(text) to authenticated, service_role;

alter table public.import_items add column duplicate_decision text check (duplicate_decision in ('keep','skip')),
  add column duplicate_signature text;
alter table public.import_batches add column duplicate_count integer not null default 0 check (duplicate_count between 0 and 500);
create index transaction_match_candidates_idx on public.transactions(user_id,account_id,transaction_type,currency,amount,account_amount,transaction_date);

create view public.import_duplicate_candidates with (security_invoker=true) as
select i.id as item_id, i.batch_id, 'transaction'::text as candidate_type, t.id as candidate_id,
       t.transaction_date, t.raw_description, t.source, null::integer as candidate_row, t.updated_at::text as version
from public.import_items i
join public.import_batches b on b.id=i.batch_id and b.user_id=i.user_id
join public.transactions t on t.user_id=i.user_id and t.account_id=b.account_id
  and t.transaction_type=i.transaction_type and t.currency=i.currency
  and t.amount=i.amount and t.account_currency=b.account_currency and t.account_amount=i.account_amount
  and t.transaction_date between i.transaction_date - 2 and i.transaction_date + 2
  and length(public.normalize_merchant(i.raw_description)) >= 4
  and public.normalize_merchant(t.raw_description)=public.normalize_merchant(i.raw_description)
where b.status = 'ready'
union all
select i.id, i.batch_id, 'file'::text, j.id, j.transaction_date, j.raw_description,
       'statement'::text, j.row_number, j.id::text
from public.import_items i
join public.import_batches b on b.id=i.batch_id and b.user_id=i.user_id
join public.import_items j on j.user_id=i.user_id and j.batch_id=i.batch_id and j.id<>i.id
  and j.transaction_type=i.transaction_type and j.currency=i.currency and j.amount=i.amount
  and j.account_amount=i.account_amount and j.transaction_date between i.transaction_date - 2 and i.transaction_date + 2
  and length(public.normalize_merchant(i.raw_description)) >= 4
  and public.normalize_merchant(j.raw_description)=public.normalize_merchant(i.raw_description)
where b.status = 'ready';
revoke all on public.import_duplicate_candidates from public, anon, authenticated;
grant select on public.import_duplicate_candidates to authenticated, service_role;

create or replace view public.import_item_details with (security_invoker=true) as
select i.id, i.batch_id, i.row_number, i.transaction_date, i.transaction_type,
       i.amount::text as amount, i.currency, i.account_amount::text as account_amount,
       i.category_id, c.name as category_name, i.raw_description, i.commission_amount::text as commission_amount,
       i.duplicate_decision,
       (select count(*)::integer from public.import_duplicate_candidates d where d.item_id=i.id) as candidate_count,
       (select md5(string_agg(d.candidate_type || ':' || d.candidate_id::text || ':' || d.version, ',' order by d.candidate_type,d.candidate_id))
        from public.import_duplicate_candidates d where d.item_id=i.id) as candidate_signature,
       i.duplicate_signature
from public.import_items i join public.categories c on c.id=i.category_id and c.user_id=i.user_id;

create table public.deduplication_decisions (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  batch_id uuid not null,
  item_id uuid not null,
  decision text not null check (decision in ('keep','skip')),
  candidate_count integer not null check (candidate_count>0),
  created_at timestamptz not null default now(),
  foreign key (user_id,batch_id) references public.import_batches(user_id,id) on delete cascade
);
alter table public.deduplication_decisions enable row level security;
revoke all on public.deduplication_decisions from public, anon, authenticated;
grant select on public.deduplication_decisions to authenticated;
create policy deduplication_read_own on public.deduplication_decisions for select to authenticated using (user_id=(select auth.uid()));

create function public.resolve_import_duplicate(p_item_id uuid, p_decision text) returns void
language plpgsql security definer set search_path='' as $$
declare v_item public.import_items%rowtype; v_batch public.import_batches%rowtype; v_signature text;
begin
  if p_decision not in ('keep','skip','clear') then raise exception 'Invalid decision' using errcode='22023'; end if;
  select i.* into v_item from public.import_items i where i.id=p_item_id and i.user_id=(select auth.uid());
  if not found then raise exception 'Import item not found' using errcode='42501'; end if;
  select * into v_batch from public.import_batches b where b.id=v_item.batch_id and b.user_id=v_item.user_id for update;
  if not found or v_batch.status <> 'ready' then raise exception 'Import is not ready' using errcode='22023'; end if;
  if p_decision='clear' then
    update public.import_items set duplicate_decision=null, duplicate_signature=null where id=v_item.id;
    return;
  end if;
  select candidate_signature into v_signature from public.import_item_details where id=v_item.id;
  if v_signature is null then raise exception 'Candidate no longer exists' using errcode='22023'; end if;
  update public.import_items set duplicate_decision=p_decision, duplicate_signature=v_signature where id=v_item.id;
end;
$$;
revoke all on function public.resolve_import_duplicate(uuid,text) from public, anon, authenticated;
grant execute on function public.resolve_import_duplicate(uuid,text) to authenticated;

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
 insert into public.transactions(user_id,account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description,source,status,import_batch_id)
 select i.user_id,v_batch.account_id,i.category_id,i.transaction_type,i.transaction_date,i.amount,i.currency,i.account_amount,v_batch.account_currency,i.raw_description,'statement','confirmed',v_batch.id
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
