-- Keep the original import and its transactions while allowing an explicit retry.
alter table public.import_batches drop constraint import_batches_status_check;
alter table public.import_batches add constraint import_batches_status_check
  check (status in ('ready','invalid','completed','cancelled','superseded'));

create function public.repeat_statement_import(p_batch_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_batch public.import_batches%rowtype;
  v_items jsonb;
  v_result jsonb;
begin
  select * into v_batch from public.import_batches
    where id=p_batch_id and user_id=(select auth.uid()) for update;
  if not found then raise exception 'Import not found' using errcode='42501'; end if;
  if v_batch.status<>'completed' then
    raise exception 'Only a completed import can be repeated' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(to_jsonb(i) order by i.row_number),'[]'::jsonb)
    into v_items from public.import_items i
    where i.batch_id=v_batch.id and i.user_id=v_batch.user_id;
  if jsonb_array_length(v_items)<>v_batch.row_count or v_batch.row_count=0 then
    raise exception 'Original import rows are unavailable' using errcode='22023';
  end if;
  update public.import_batches set status='superseded' where id=v_batch.id;
  v_result:=public.register_statement_import(
    v_batch.user_id,v_batch.account_id,v_batch.account_currency,
    v_batch.original_filename,v_batch.file_sha256,v_items,'[]'::jsonb,0,v_batch.format
  );
  if coalesce((v_result->>'duplicate')::boolean,true) then
    raise exception 'Another import is already in progress' using errcode='23505';
  end if;
  return (v_result->>'id')::uuid;
end;
$$;
revoke all on function public.repeat_statement_import(uuid) from public,anon,authenticated;
grant execute on function public.repeat_statement_import(uuid) to authenticated;
