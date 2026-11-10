-- A minimal, read-only connection check. No user or financial data is exposed.
create function public.cash_radar_health()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select 'ok'::text;
$$;

revoke all on function public.cash_radar_health() from public;
grant execute on function public.cash_radar_health() to anon, authenticated;
