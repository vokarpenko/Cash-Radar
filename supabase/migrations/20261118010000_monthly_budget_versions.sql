-- Versioned monthly limits retain history when a recurring budget is changed.
create table public.budget_versions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 category_id uuid not null,
 category_kind text generated always as ('expense'::text) stored,
 effective_month date not null check (effective_month = date_trunc('month', effective_month)::date and effective_month >= date '1900-01-01' and effective_month < date '2101-01-01'),
 currency text not null check (currency in ('AMD','RUB','USD','EUR')),
 amount numeric check (amount > 0 and amount < 1000000000000000000 and amount = trunc(amount, 2)),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint budget_versions_category_fk foreign key (user_id, category_id, category_kind) references public.categories(user_id, id, kind),
 constraint budget_versions_unique unique (user_id, category_id, effective_month)
);
create index budget_versions_lookup on public.budget_versions(user_id, category_id, effective_month desc);
alter table public.budget_versions enable row level security;
revoke all on public.budget_versions from public, anon, authenticated;
grant select on public.budget_versions to authenticated;
grant all on public.budget_versions to service_role;
create policy budget_versions_read_own on public.budget_versions for select to authenticated using ((select auth.uid()) = user_id);

-- A null amount stops recurrence starting in the selected month.
create function public.save_budget_version(p_category_id uuid, p_effective_month date, p_currency text, p_amount numeric)
returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid := (select auth.uid()); result uuid;
begin
 if u is null then raise exception 'Authentication required' using errcode = '42501'; end if;
 if p_category_id is null or p_effective_month is null or p_effective_month <> date_trunc('month',p_effective_month)::date
    or p_effective_month < date '1900-01-01' or p_effective_month >= date '2101-01-01'
    or p_currency is null or p_currency not in ('AMD','RUB','USD','EUR')
    or (p_amount is not null and (p_amount <= 0 or p_amount >= 1000000000000000000 or p_amount <> trunc(p_amount,2))) then
   raise exception 'Invalid budget' using errcode='22023';
 end if;
 if not exists(select 1 from public.categories where id=p_category_id and user_id=u and kind='expense') then
   raise exception 'Category unavailable' using errcode='22023';
 end if;
 insert into public.budget_versions(user_id,category_id,effective_month,currency,amount)
 values(u,p_category_id,p_effective_month,p_currency,p_amount)
 on conflict(user_id,category_id,effective_month) do update set currency=excluded.currency,amount=excluded.amount,updated_at=now()
 returning id into result;
 return result;
end $$;
revoke all on function public.save_budget_version(uuid,date,text,numeric) from public,anon,authenticated;
grant execute on function public.save_budget_version(uuid,date,text,numeric) to authenticated;
