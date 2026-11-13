-- Explicit CSV categories remain manual; bank rows may be re-evaluated before confirmation.
drop trigger import_item_categorization on public.import_items;
create trigger import_item_categorization before insert or update of raw_data on public.import_items
 for each row execute function private.categorize_import_item();
create function public.reapply_import_categories(p_batch_id uuid) returns integer
language plpgsql security definer set search_path='' as $$
declare v_batch public.import_batches%rowtype; v_count integer;
begin
 select * into v_batch from public.import_batches where id=p_batch_id and user_id=(select auth.uid()) for update;
 if not found then raise exception 'Import not found' using errcode='42501'; end if;
 if v_batch.status<>'ready' then raise exception 'Import is not ready' using errcode='22023'; end if;
 update public.import_items set raw_data=raw_data where batch_id=v_batch.id and user_id=v_batch.user_id;
 get diagnostics v_count=row_count;
 return v_count;
end;
$$;
revoke all on function public.reapply_import_categories(uuid) from public,anon,authenticated;
grant execute on function public.reapply_import_categories(uuid) to authenticated;

-- Report provenance for earlier bank imports without changing any category or amount.
update public.transactions t set categorization_source='fallback'
from public.import_batches b where t.import_batch_id=b.id and t.user_id=b.user_id and b.format in ('acba_xlsx_v1','ameria_xlsx_v1');
update public.import_items i set categorization_source='fallback'
from public.import_batches b where i.batch_id=b.id and i.user_id=b.user_id and b.format in ('acba_xlsx_v1','ameria_xlsx_v1');
