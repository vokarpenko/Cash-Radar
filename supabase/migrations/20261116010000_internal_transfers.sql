-- Transfers retain the two underlying postings; account balances remain unchanged.
alter table public.transactions add constraint transactions_owner_id_unique unique (user_id,id);
create table public.transfer_groups (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 debit_id uuid not null, credit_id uuid not null, fee_id uuid,
 request_id uuid, request_signature text,
 unique(user_id,request_id), check((request_id is null)=(request_signature is null)),
 created_at timestamptz not null default now(),
 unique(user_id,debit_id), unique(user_id,credit_id), unique(user_id,fee_id),
 foreign key(user_id,debit_id) references public.transactions(user_id,id),
 foreign key(user_id,credit_id) references public.transactions(user_id,id),
 foreign key(user_id,fee_id) references public.transactions(user_id,id),
 check(debit_id<>credit_id and (fee_id is null or fee_id not in (debit_id,credit_id)))
);
create table public.transfer_rejections (
 user_id uuid not null references auth.users(id) on delete cascade,
 debit_id uuid not null,credit_id uuid not null,signature text not null,
 primary key(user_id,debit_id,credit_id),
 foreign key(user_id,debit_id) references public.transactions(user_id,id) on delete cascade,
 foreign key(user_id,credit_id) references public.transactions(user_id,id) on delete cascade
);
alter table public.transfer_groups enable row level security;
alter table public.transfer_rejections enable row level security;
revoke all on public.transfer_groups,public.transfer_rejections from public,anon,authenticated;
grant select on public.transfer_groups,public.transfer_rejections to authenticated;
grant all on public.transfer_groups,public.transfer_rejections to service_role;
create policy transfer_groups_read on public.transfer_groups for select to authenticated using(user_id=(select auth.uid()));
create policy transfer_rejections_read on public.transfer_rejections for select to authenticated using(user_id=(select auth.uid()));

-- Financial fields are immutable while linked; unlink before editing or deleting.
create function private.protect_linked_transaction() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' and not exists(select 1 from auth.users where id=old.user_id) then return old; end if;
 if exists(select 1 from public.transfer_groups g where g.user_id=old.user_id and old.id in (g.debit_id,g.credit_id,g.fee_id)) then
  raise exception 'Unlink transfer before editing or deleting its operations' using errcode='23514';
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end; $$;
create trigger transactions_protect_transfer before update or delete on public.transactions for each row execute function private.protect_linked_transaction();

-- A candidate is only a suggestion; different currencies are displayed without
-- estimating an exchange rate. Rejection expires if either posting changes.
create view public.transfer_candidates with (security_invoker=true) as
select d.id debit_id,c.id credit_id,d.transaction_date debit_date,c.transaction_date credit_date,
 d.account_id debit_account_id,da.name debit_account,c.account_id credit_account_id,ca.name credit_account,
 d.account_amount::text debit_amount,d.account_currency debit_currency,c.account_amount::text credit_amount,c.account_currency credit_currency,
 d.raw_description debit_description,c.raw_description credit_description,
 (d.account_currency=c.account_currency and d.account_amount=c.account_amount) exact_amount,
 abs(d.transaction_date-c.transaction_date) days_apart,
 d.updated_at::text debit_updated_at,c.updated_at::text credit_updated_at
from public.transactions d join public.transactions c on c.user_id=d.user_id and c.transaction_type='income' and c.account_id<>d.account_id
 and c.transaction_date between d.transaction_date-3 and d.transaction_date+3
 and (c.account_currency<>d.account_currency or c.account_amount=d.account_amount)
join public.accounts da on da.id=d.account_id and da.user_id=d.user_id
join public.accounts ca on ca.id=c.account_id and ca.user_id=c.user_id
where d.transaction_type='expense'
 and not exists(select 1 from public.transfer_groups g where g.user_id=d.user_id and (d.id in(g.debit_id,g.credit_id,g.fee_id) or c.id in(g.debit_id,g.credit_id,g.fee_id)))
 and not exists(select 1 from public.transfer_rejections r where r.user_id=d.user_id and r.debit_id=d.id and r.credit_id=c.id and r.signature=md5((to_jsonb(d)-'updated_at'-'created_at')::text||':'||(to_jsonb(c)-'updated_at'-'created_at')::text));
revoke all on public.transfer_candidates from public,anon,authenticated;
grant select on public.transfer_candidates to authenticated,service_role;

create function public.confirm_transfer(p_debit uuid,p_credit uuid,p_fee uuid default null,p_debit_version timestamptz default null,p_credit_version timestamptz default null,p_fee_version timestamptz default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid:=(select auth.uid()); d public.transactions%rowtype; c public.transactions%rowtype; f public.transactions%rowtype; v_id uuid;
begin
 if v_user is null or p_debit is null or p_credit is null or p_debit=p_credit or p_fee in(p_debit,p_credit) then raise exception 'Invalid transfer' using errcode='22023'; end if;
 -- Consistent lock order prevents concurrent pairings from sharing a posting.
 perform 1 from public.transactions where user_id=v_user and id in(p_debit,p_credit,p_fee) order by id for update;
 select * into d from public.transactions where user_id=v_user and id=p_debit;
 select * into c from public.transactions where user_id=v_user and id=p_credit;
 if d.id is null or c.id is null or d.transaction_type<>'expense' or c.transaction_type<>'income' or d.account_id=c.account_id then raise exception 'Transfer operations unavailable' using errcode='22023'; end if;
 if (p_debit_version is not null and d.updated_at is distinct from p_debit_version) or (p_credit_version is not null and c.updated_at is distinct from p_credit_version) then
  raise exception 'Transfer operations changed; refresh before confirmation' using errcode='40001';
 end if;
 if p_fee is not null then
  select * into f from public.transactions where user_id=v_user and id=p_fee;
  if f.id is null or f.transaction_type<>'expense' or f.account_id<>d.account_id then raise exception 'Fee operation unavailable' using errcode='22023'; end if;
  if p_fee_version is not null and f.updated_at is distinct from p_fee_version then raise exception 'Fee operation changed; refresh before confirmation' using errcode='40001'; end if;
 end if;
 if exists(select 1 from public.transfer_groups g where g.user_id=v_user and (g.debit_id in(p_debit,p_credit,p_fee) or g.credit_id in(p_debit,p_credit,p_fee) or g.fee_id in(p_debit,p_credit,p_fee))) then raise exception 'Operation already linked' using errcode='23505'; end if;
 insert into public.transfer_groups(user_id,debit_id,credit_id,fee_id) values(v_user,p_debit,p_credit,p_fee) returning id into v_id;
 return v_id;
end; $$;
create function public.unlink_transfer(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 delete from public.transfer_groups where id=p_id and user_id=(select auth.uid());
 if not found then raise exception 'Transfer unavailable' using errcode='42501'; end if;
end; $$;
create function public.reject_transfer_candidate(p_debit uuid,p_credit uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid:=(select auth.uid()); v_signature text;
begin
 select md5((to_jsonb(d)-'updated_at'-'created_at')::text||':'||(to_jsonb(c)-'updated_at'-'created_at')::text) into v_signature from public.transactions d join public.transactions c on c.user_id=d.user_id
 where d.id=p_debit and c.id=p_credit and d.user_id=v_user and exists(select 1 from public.transfer_candidates where debit_id=d.id and credit_id=c.id);
 if v_signature is null then raise exception 'Candidate unavailable' using errcode='22023'; end if;
 insert into public.transfer_rejections(user_id,debit_id,credit_id,signature) values(v_user,p_debit,p_credit,v_signature)
 on conflict(user_id,debit_id,credit_id) do update set signature=excluded.signature;
end; $$;
revoke all on function public.confirm_transfer(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz),public.unlink_transfer(uuid),public.reject_transfer_candidate(uuid,uuid) from public,anon,authenticated;
grant execute on function public.confirm_transfer(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz),public.unlink_transfer(uuid),public.reject_transfer_candidate(uuid,uuid) to authenticated;

-- Separate source for statistics; fee postings remain expenses.
create view public.income_expense_transactions with (security_invoker=true) as
select t.* from public.transactions t where not exists(select 1 from public.transfer_groups g where g.user_id=t.user_id and t.id in(g.debit_id,g.credit_id));
revoke all on public.income_expense_transactions from public,anon,authenticated;
grant select on public.income_expense_transactions to authenticated,service_role;

-- Append transfer metadata while preserving the existing public view columns.
create or replace view public.transaction_details with (security_invoker=true) as
select t.id,t.account_id,a.name as account_name,a.is_active as account_active,t.category_id,c.name as category_name,
 t.transaction_type,t.transaction_date,t.amount::text as amount,t.currency,t.account_amount::text as account_amount,
 t.account_currency,t.raw_description,t.source,t.status,t.created_at,t.merchant_name,t.mcc,t.categorization_source,
 (select g.id from public.transfer_groups g where g.user_id=t.user_id and t.id in(g.debit_id,g.credit_id) limit 1) as transfer_group_id,
 (select g.id from public.transfer_groups g where g.user_id=t.user_id and t.id=g.fee_id limit 1) as transfer_fee_group_id,
 t.updated_at::text as updated_at
from public.transactions t join public.accounts a on a.user_id=t.user_id and a.id=t.account_id
join public.categories c on c.user_id=t.user_id and c.id=t.category_id;

-- Create both legs atomically, optionally recording a separate source-account fee.
create function public.create_manual_transfer(p_from uuid,p_to uuid,p_date date,p_from_amount numeric,p_to_amount numeric,p_fee numeric default 0,p_description text default null,p_request_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=(select auth.uid()); a public.accounts%rowtype; b public.accounts%rowtype; expense uuid; income uuid; d uuid; c uuid; f uuid; v_id uuid; v_signature text; v_existing text;
begin
 if u is null or p_request_id is null or p_from=p_to or p_date not between date '1900-01-01' and date '2100-12-31'
  or p_from_amount is null or p_to_amount is null or p_fee is null
  or not (p_from_amount>0 and p_from_amount<1e18 and p_from_amount=trunc(p_from_amount,2))
  or not (p_to_amount>0 and p_to_amount<1e18 and p_to_amount=trunc(p_to_amount,2))
  or not (p_fee>=0 and p_fee<1e18 and p_fee=trunc(p_fee,2))
  or (p_description is not null and length(btrim(p_description))>500) then raise exception 'Invalid transfer amounts' using errcode='22023'; end if;
 perform 1 from public.accounts where user_id=u and id in(p_from,p_to) order by id for update;
 select * into a from public.accounts where user_id=u and id=p_from and is_active;
 select * into b from public.accounts where user_id=u and id=p_to and is_active;
 if a.id is null or b.id is null then raise exception 'Account unavailable' using errcode='22023'; end if;
 -- Repeated requests use the same client-generated identifier and parameters.
 v_signature:=md5(jsonb_build_array(p_from,p_to,p_date,p_from_amount,p_to_amount,p_fee,nullif(btrim(p_description),''))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text||':'||p_request_id::text,0));
 select id,request_signature into v_id,v_existing from public.transfer_groups where user_id=u and request_id=p_request_id;
 if v_id is not null then
  if v_existing<>v_signature then raise exception 'Transfer request identifier reused with different details' using errcode='22023'; end if;
  return v_id;
 end if;

 if a.currency=b.currency and p_from_amount<>p_to_amount then raise exception 'Same currency transfer amounts must match; specify fee separately' using errcode='22023'; end if;
 select id into expense from public.categories where user_id=u and kind='expense' order by (name='Прочие расходы') desc,id limit 1;
 select id into income from public.categories where user_id=u and kind='income' order by (name='Прочие доходы') desc,id limit 1;
 if expense is null or income is null then raise exception 'Income or expense category unavailable' using errcode='22023'; end if;
 insert into public.transactions(user_id,account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description)
 values(u,a.id,expense,'expense',p_date,p_from_amount,a.currency,p_from_amount,a.currency,nullif(btrim(p_description),'')) returning id into d;
 insert into public.transactions(user_id,account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description)
 values(u,b.id,income,'income',p_date,p_to_amount,b.currency,p_to_amount,b.currency,nullif(btrim(p_description),'')) returning id into c;
 if p_fee>0 then
  insert into public.transactions(user_id,account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description)
  values(u,a.id,expense,'expense',p_date,p_fee,a.currency,p_fee,a.currency,'Комиссия за перевод') returning id into f;
 end if;
 v_id:=public.confirm_transfer(d,c,f);
 update public.transfer_groups set request_id=p_request_id,request_signature=v_signature where id=v_id and user_id=u;
 return v_id;
end; $$;

-- Explicitly convert an existing withdrawal to a movement into a cash wallet.
create function public.transfer_to_cash(p_debit uuid,p_cash uuid,p_debit_version timestamptz default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=(select auth.uid()); d public.transactions%rowtype; wallet public.accounts%rowtype; income uuid; c uuid;
begin
 select * into d from public.transactions where user_id=u and id=p_debit for update;
 select * into wallet from public.accounts where user_id=u and id=p_cash and account_type='cash' and is_active for update;
 if d.id is null or d.transaction_type<>'expense' or wallet.id is null or d.account_id=wallet.id or d.account_currency<>wallet.currency then raise exception 'Withdrawal or cash wallet unavailable' using errcode='22023'; end if;
 if p_debit_version is not null and d.updated_at is distinct from p_debit_version then raise exception 'Withdrawal changed; refresh before confirmation' using errcode='40001'; end if;
 if exists(select 1 from public.transfer_groups g where g.user_id=u and d.id in(g.debit_id,g.credit_id,g.fee_id)) then raise exception 'Operation already linked' using errcode='23505'; end if;
 select id into income from public.categories where user_id=u and kind='income' order by (name='Прочие доходы') desc,id limit 1;
 if income is null then raise exception 'Income category unavailable' using errcode='22023'; end if;
 insert into public.transactions(user_id,account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description)
 values(u,wallet.id,income,'income',d.transaction_date,d.account_amount,wallet.currency,d.account_amount,wallet.currency,'Снятие наличных') returning id into c;
 return public.confirm_transfer(d.id,c,null);
end; $$;
revoke all on function public.create_manual_transfer(uuid,uuid,date,numeric,numeric,numeric,text,uuid),public.transfer_to_cash(uuid,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.create_manual_transfer(uuid,uuid,date,numeric,numeric,numeric,text,uuid),public.transfer_to_cash(uuid,uuid,timestamptz) to authenticated;
create view public.transfer_group_details with (security_invoker=true) as
select g.id,g.debit_id,g.credit_id,g.fee_id,g.created_at,
 da.name as debit_account,ca.name as credit_account,d.transaction_date debit_date,c.transaction_date credit_date,
 d.account_amount::text debit_amount,d.account_currency debit_currency,c.account_amount::text credit_amount,c.account_currency credit_currency,
 f.account_amount::text fee_amount,f.account_currency fee_currency
from public.transfer_groups g
join public.transactions d on d.user_id=g.user_id and d.id=g.debit_id
join public.transactions c on c.user_id=g.user_id and c.id=g.credit_id
join public.accounts da on da.user_id=g.user_id and da.id=d.account_id
join public.accounts ca on ca.user_id=g.user_id and ca.id=c.account_id
left join public.transactions f on f.user_id=g.user_id and f.id=g.fee_id;
revoke all on public.transfer_group_details from public,anon,authenticated;
grant select on public.transfer_group_details to authenticated,service_role;
