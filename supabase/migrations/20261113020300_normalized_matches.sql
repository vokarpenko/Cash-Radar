-- Normalized merchant aliases also suggest possible matches; no matches are removed automatically.
create or replace view public.import_duplicate_candidates with (security_invoker=true) as
select i.id as item_id, i.batch_id, 'transaction'::text as candidate_type, t.id as candidate_id,
       t.transaction_date, t.raw_description, t.source, null::integer as candidate_row, t.updated_at::text as version
from public.import_items i
join public.import_batches b on b.id=i.batch_id and b.user_id=i.user_id
join public.transactions t on t.user_id=i.user_id and t.account_id=b.account_id
  and t.transaction_type=i.transaction_type and t.currency=i.currency
  and t.amount=i.amount and t.account_currency=b.account_currency and t.account_amount=i.account_amount
  and t.transaction_date between i.transaction_date - 2 and i.transaction_date + 2
  and length(coalesce(nullif(i.normalized_merchant,''),public.normalize_merchant(i.raw_description))) >= 4
  and coalesce(nullif(t.normalized_merchant,''),public.normalize_merchant(t.raw_description))=coalesce(nullif(i.normalized_merchant,''),public.normalize_merchant(i.raw_description))
where b.status = 'ready'
union all
select i.id, i.batch_id, 'file'::text, j.id, j.transaction_date, j.raw_description,
       'statement'::text, j.row_number, j.id::text
from public.import_items i
join public.import_batches b on b.id=i.batch_id and b.user_id=i.user_id
join public.import_items j on j.user_id=i.user_id and j.batch_id=i.batch_id and j.id<>i.id
  and j.transaction_type=i.transaction_type and j.currency=i.currency and j.amount=i.amount
  and j.account_amount=i.account_amount and j.transaction_date between i.transaction_date - 2 and i.transaction_date + 2
  and length(coalesce(nullif(i.normalized_merchant,''),public.normalize_merchant(i.raw_description))) >= 4
  and coalesce(nullif(j.normalized_merchant,''),public.normalize_merchant(j.raw_description))=coalesce(nullif(i.normalized_merchant,''),public.normalize_merchant(i.raw_description))
where b.status = 'ready';
