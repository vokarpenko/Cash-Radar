-- Explicit rules and learned corrections belong to their owner and category kind.
create table public.category_rules (
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 kind text not null check (kind in ('income','expense')),
 match_type text not null check (match_type in ('merchant_contains','merchant_exact','mcc')),
 pattern text not null check (length(btrim(pattern)) between 3 and 120),
 category_id uuid not null, priority integer not null default 100 check (priority between 0 and 10000),
 enabled boolean not null default true, created_at timestamptz not null default now(),
 foreign key(user_id,category_id,kind) references public.categories(user_id,id,kind),
 check (match_type<>'mcc' or pattern ~ '^[0-9]{4}$'),
 check (match_type='mcc' or length(public.normalize_merchant(pattern))>=3)
);
create index category_rules_owner_priority_idx on public.category_rules(user_id,kind,priority desc);
create table public.merchant_aliases (
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 kind text not null check (kind in ('income','expense')),
 alias text not null check (length(btrim(alias)) between 3 and 120 and length(public.normalize_merchant(alias))>=3),
 canonical_name text not null check (length(btrim(canonical_name)) between 3 and 120),
 category_id uuid, created_at timestamptz not null default now(),
 foreign key(user_id,category_id,kind) references public.categories(user_id,id,kind)
);
create unique index merchant_alias_unique on public.merchant_aliases(user_id,kind,public.normalize_merchant(alias));
create table public.category_feedback (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check (kind in ('income','expense')),
 merchant_key text not null check (length(merchant_key) between 4 and 500),
 category_id uuid not null, updated_at timestamptz not null default now(),
 unique(user_id,kind,merchant_key),
 foreign key(user_id,category_id,kind) references public.categories(user_id,id,kind)
);
alter table public.category_rules enable row level security;
alter table public.merchant_aliases enable row level security;
alter table public.category_feedback enable row level security;
revoke all on public.category_rules,public.merchant_aliases,public.category_feedback from public,anon,authenticated;
grant select,insert,update,delete on public.category_rules,public.merchant_aliases to authenticated;
grant select,delete on public.category_feedback to authenticated;
grant all on public.category_rules,public.merchant_aliases,public.category_feedback to service_role;
create policy category_rules_owner on public.category_rules for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy merchant_aliases_owner on public.merchant_aliases for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy category_feedback_read on public.category_feedback for select to authenticated using (user_id=(select auth.uid()));
create policy category_feedback_delete on public.category_feedback for delete to authenticated using (user_id=(select auth.uid()));

alter table public.import_items add column merchant_name text, add column mcc text check (mcc is null or mcc ~ '^[0-9]{4}$'),
 add column categorization_source text not null default 'manual' check (categorization_source in ('manual','rule','alias','mcc','history','fallback'));
alter table public.transactions add column merchant_name text, add column mcc text check (mcc is null or mcc ~ '^[0-9]{4}$'),
 add column categorization_source text not null default 'manual' check (categorization_source in ('manual','rule','alias','mcc','history','fallback'));

-- Returns only categories of the same owner and transaction kind.
create function private.evaluate_category(p_user uuid,p_kind text,p_merchant text,p_mcc text,p_default uuid)
returns table(category_id uuid, source text, normalized_merchant text)
language plpgsql stable security definer set search_path='' as $$
declare v_key text:=public.normalize_merchant(p_merchant); v_canonical text; v_alias_category uuid; v_category uuid;
begin
 select r.category_id into v_category from public.category_rules r
 where r.user_id=p_user and r.kind=p_kind and r.enabled and r.match_type in ('merchant_contains','merchant_exact')
 and ((r.match_type='merchant_exact' and v_key=public.normalize_merchant(r.pattern))
   or (r.match_type='merchant_contains' and strpos(v_key,public.normalize_merchant(r.pattern))>0))
 order by r.priority desc,length(public.normalize_merchant(r.pattern)) desc,r.created_at,r.id limit 1;
 if found then return query select v_category,'rule'::text,v_key; return; end if;
 select public.normalize_merchant(a.canonical_name),a.category_id into v_canonical,v_alias_category
 from public.merchant_aliases a where a.user_id=p_user and a.kind=p_kind and public.normalize_merchant(a.alias)=v_key order by a.id limit 1;
 if found then
   if v_alias_category is not null then return query select v_alias_category,'alias'::text,v_canonical; return; end if;
   select r.category_id into v_category from public.category_rules r
   where r.user_id=p_user and r.kind=p_kind and r.enabled and r.match_type in ('merchant_contains','merchant_exact')
   and ((r.match_type='merchant_exact' and v_canonical=public.normalize_merchant(r.pattern))
     or (r.match_type='merchant_contains' and strpos(v_canonical,public.normalize_merchant(r.pattern))>0))
   order by r.priority desc,length(public.normalize_merchant(r.pattern)) desc,r.created_at,r.id limit 1;
   if found then return query select v_category,'alias'::text,v_canonical; return; end if;
 end if;
 select r.category_id into v_category from public.category_rules r where r.user_id=p_user and r.kind=p_kind and r.enabled and r.match_type='mcc' and r.pattern=p_mcc
 order by r.priority desc,r.created_at,r.id limit 1;
 if found then return query select v_category,'mcc'::text,coalesce(v_canonical,v_key); return; end if;
 select f.category_id into v_category from public.category_feedback f
 where f.user_id=p_user and f.kind=p_kind and f.merchant_key=coalesce(v_canonical,v_key) limit 1;
 if found then return query select v_category,'history'::text,coalesce(v_canonical,v_key); return; end if;
 return query select p_default,'fallback'::text,coalesce(v_canonical,v_key);
end;
$$;
revoke all on function private.evaluate_category(uuid,text,text,text,uuid) from public,anon,authenticated;

create function private.categorize_import_item() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_format text; v_result record;
begin
 select format into v_format from public.import_batches where id=new.batch_id and user_id=new.user_id;
 if v_format='cashradar_csv_v1' then new.categorization_source:='manual'; return new; end if;
 -- The ACBA merchant is a dedicated column; other parsers retain the entire raw description.
 new.merchant_name:=left(nullif(btrim(coalesce(new.raw_data->>'AD',new.raw_description,'')),''),500);
 if coalesce(new.raw_data->>'mcc','') ~ '^[0-9]{4}$' then new.mcc:=new.raw_data->>'mcc'; end if;
 select * into v_result from private.evaluate_category(new.user_id,new.transaction_type,new.merchant_name,new.mcc,new.category_id);
 new.category_id:=v_result.category_id; new.categorization_source:=v_result.source;
 return new;
end;
$$;
create trigger import_item_categorization before insert on public.import_items for each row execute function private.categorize_import_item();

create function private.record_category_correction() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_key text; v_alias text;
begin
 if old.category_id is distinct from new.category_id then
   new.categorization_source:='manual';
   v_key:=public.normalize_merchant(coalesce(nullif(new.merchant_name,''),new.raw_description));
   select public.normalize_merchant(a.canonical_name) into v_alias from public.merchant_aliases a
     where a.user_id=new.user_id and a.kind=new.transaction_type and public.normalize_merchant(a.alias)=v_key limit 1;
   v_key:=coalesce(v_alias,v_key);
   if length(v_key) between 4 and 500 then
     insert into public.category_feedback(user_id,kind,merchant_key,category_id)
     values(new.user_id,new.transaction_type,v_key,new.category_id)
     on conflict(user_id,kind,merchant_key) do update set category_id=excluded.category_id,updated_at=now();
   end if;
 end if;
 return new;
end;
$$;
create trigger transactions_record_category_correction before update on public.transactions for each row execute function private.record_category_correction();

create or replace view public.import_item_details with (security_invoker=true) as
select i.id, i.batch_id, i.row_number, i.transaction_date, i.transaction_type,
       i.amount::text as amount, i.currency, i.account_amount::text as account_amount,
       i.category_id, c.name as category_name, i.raw_description, i.commission_amount::text as commission_amount,
       i.duplicate_decision,
       (select count(*)::integer from public.import_duplicate_candidates d where d.item_id=i.id) as candidate_count,
       (select md5(string_agg(d.candidate_type || ':' || d.candidate_id::text || ':' || d.version, ',' order by d.candidate_type,d.candidate_id))
        from public.import_duplicate_candidates d where d.item_id=i.id) as candidate_signature,
       i.duplicate_signature, i.merchant_name, i.mcc, i.categorization_source
from public.import_items i join public.categories c on c.id=i.category_id and c.user_id=i.user_id;

create or replace view public.transaction_details with (security_invoker=true) as
select t.id,t.account_id,a.name as account_name,a.is_active as account_active,t.category_id,c.name as category_name,
       t.transaction_type,t.transaction_date,t.amount::text as amount,t.currency,t.account_amount::text as account_amount,
       t.account_currency,t.raw_description,t.source,t.status,t.created_at,t.merchant_name,t.mcc,t.categorization_source
from public.transactions t join public.accounts a on a.user_id=t.user_id and a.id=t.account_id
join public.categories c on c.user_id=t.user_id and c.id=t.category_id;

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
 insert into public.transactions(user_id,account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description,source,status,import_batch_id,merchant_name,mcc,categorization_source)
 select i.user_id,v_batch.account_id,i.category_id,i.transaction_type,i.transaction_date,i.amount,i.currency,i.account_amount,v_batch.account_currency,i.raw_description,'statement','confirmed',v_batch.id,i.merchant_name,i.mcc,i.categorization_source
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
