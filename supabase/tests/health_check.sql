-- Run against an isolated database after applying the migration.
begin;

do $$
begin
  if not has_function_privilege('anon', 'public.cash_radar_health()', 'execute') then
    raise exception 'anon cannot execute the health check';
  end if;
  if not has_function_privilege('authenticated', 'public.cash_radar_health()', 'execute') then
    raise exception 'authenticated cannot execute the health check';
  end if;
  if exists (
    select 1
    from pg_catalog.pg_proc p,
      pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
    where p.oid = 'public.cash_radar_health()'::regprocedure
      and a.grantee = 0 and a.privilege_type = 'EXECUTE'
  ) then
    raise exception 'PUBLIC has execute access';
  end if;
  if (select prosecdef from pg_catalog.pg_proc
      where oid = 'public.cash_radar_health()'::regprocedure) then
    raise exception 'health check must use invoker privileges';
  end if;
end;
$$;

set local role anon;
do $$
begin
  if public.cash_radar_health() <> 'ok' then
    raise exception 'unexpected health check response';
  end if;
end;
$$;
reset role;
rollback;
