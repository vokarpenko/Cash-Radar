-- Cancellation releases staged category references without deleting original files.
alter table public.import_batches drop constraint import_batches_status_check;
alter table public.import_batches add constraint import_batches_status_check
  check (status in ('ready','invalid','completed','cancelled'));

create function public.cancel_statement_import(p_batch_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_batch public.import_batches%rowtype;
begin
  select * into v_batch from public.import_batches where id = p_batch_id and user_id = (select auth.uid()) for update;
  if not found then raise exception 'Import not found' using errcode = '42501'; end if;
  if v_batch.status = 'completed' then raise exception 'Completed import cannot be cancelled' using errcode = '22023'; end if;
  if v_batch.status = 'cancelled' then return jsonb_build_object('already_cancelled', true); end if;
  delete from public.import_items where batch_id = v_batch.id and user_id = v_batch.user_id;
  update public.import_batches set status = 'cancelled' where id = v_batch.id;
  return jsonb_build_object('already_cancelled', false);
end;
$$;
revoke all on function public.cancel_statement_import(uuid) from public, anon, authenticated;
grant execute on function public.cancel_statement_import(uuid) to authenticated;
