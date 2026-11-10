-- Lock the owner's existing categories in addition to the advisory lock.
-- This rejects stale concurrent snapshots at REPEATABLE READ as well as
-- preventing concurrent hierarchy edits at READ COMMITTED.
create or replace function private.check_category_ancestry()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.parent_id is null then
    return new;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text, 0));
  perform 1 from public.categories c
    where c.user_id = new.user_id order by c.id for update;
  if exists (
    with recursive ancestors (id, parent_id) as (
      select c.id, c.parent_id from public.categories c
      where c.user_id = new.user_id and c.id = new.parent_id
      union
      select c.id, c.parent_id from public.categories c
      join ancestors a on c.id = a.parent_id
      where c.user_id = new.user_id
    )
    select 1 from ancestors where id = new.id
  ) then
    raise exception 'Category hierarchy cannot contain a cycle' using errcode = '23514';
  end if;
  return new;
end;
$$;
