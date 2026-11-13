-- An exact, user-owned merchant mapping. Disabled mappings remain as a tombstone
-- so that a subsequent import does not silently ask the provider again.
create table public.ai_merchant_rules (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('expense','income')),
 merchant_key text not null check(length(merchant_key) between 3 and 500),
 merchant_name text not null check(length(merchant_name) between 3 and 80),
 category_id uuid not null,
 confidence numeric not null check(confidence between 0 and 1),
 model text not null, prompt_version text not null,
 enabled boolean not null default true, created_at timestamptz not null default now(),
 unique(user_id,kind,merchant_key),
 foreign key(user_id,category_id,kind) references public.categories(user_id,id,kind)
);
alter table public.ai_merchant_rules enable row level security;
revoke all on public.ai_merchant_rules from public,anon,authenticated;
grant select,delete on public.ai_merchant_rules to authenticated;
grant update(enabled,category_id) on public.ai_merchant_rules to authenticated;
grant all on public.ai_merchant_rules to service_role;
create policy ai_rules_owner on public.ai_merchant_rules for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));

create table public.ai_suggestions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('expense','income')), merchant_key text not null,
 merchant_name text not null, category_id uuid not null, confidence numeric not null check(confidence between 0 and 1),
 model text not null, prompt_version text not null, status text not null default 'pending' check(status in ('pending','dismissed')),
 created_at timestamptz not null default now(), unique(user_id,kind,merchant_key),
 foreign key(user_id,category_id,kind) references public.categories(user_id,id,kind)
);
alter table public.ai_suggestions enable row level security;
revoke all on public.ai_suggestions from public,anon,authenticated;
grant select,delete on public.ai_suggestions to authenticated;
grant all on public.ai_suggestions to service_role;
create policy ai_suggestions_owner on public.ai_suggestions for select to authenticated using(user_id=(select auth.uid()));
create policy ai_suggestions_delete on public.ai_suggestions for delete to authenticated using(user_id=(select auth.uid()));

-- Server-only thresholds are adjustable without changing client code.
create table private.ai_configuration (
 singleton boolean primary key default true check(singleton),
 high_confidence numeric not null default 0.9,
 medium_confidence numeric not null default 0.6,
 check(medium_confidence between 0 and 1 and high_confidence between medium_confidence and 1)
);
insert into private.ai_configuration(singleton) values(true);
revoke all on private.ai_configuration from public,anon,authenticated;

create table private.ai_request_locks (user_id uuid primary key references auth.users(id) on delete cascade, token uuid not null, expires_at timestamptz not null);
revoke all on private.ai_request_locks from public,anon,authenticated;

alter table public.import_items drop constraint import_items_categorization_source_check;
alter table public.import_items add constraint import_items_categorization_source_check check(categorization_source in ('manual','rule','alias','mcc','history','fallback','ai'));
alter table public.transactions drop constraint transactions_categorization_source_check;
alter table public.transactions add constraint transactions_categorization_source_check check(categorization_source in ('manual','rule','alias','mcc','history','fallback','ai'));

create or replace function private.evaluate_category(p_user uuid,p_kind text,p_merchant text,p_mcc text,p_default uuid)
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
 select r.category_id into v_category from public.ai_merchant_rules r
 where r.user_id=p_user and r.kind=p_kind and r.enabled and r.merchant_key=coalesce(v_canonical,v_key) limit 1;
 if found then return query select v_category,'ai'::text,coalesce(v_canonical,v_key); return; end if;
 return query select p_default,'fallback'::text,coalesce(v_canonical,v_key);
end;
$$;
-- The preview shows exact names to the owner. Nothing is sent to Google here.
create function private.ai_candidates(p_user uuid,p_batch uuid)
returns table(group_id text, merchant text, kind text, item_count bigint)
language sql stable security definer set search_path='' as $$
 select pg_catalog.md5(i.transaction_type||':'||public.normalize_merchant(coalesce(nullif(i.merchant_name,''),i.raw_description))),
        min(coalesce(nullif(i.merchant_name,''),i.raw_description)), i.transaction_type, count(*)
 from public.import_items i join public.import_batches b on b.id=i.batch_id and b.user_id=i.user_id
 cross join lateral private.evaluate_category(i.user_id,i.transaction_type,coalesce(nullif(i.merchant_name,''),i.raw_description),i.mcc,i.category_id) e
 where i.user_id=p_user and i.batch_id=p_batch and b.status in ('ready','completed')
   and b.format in ('acba_xlsx_v1','ameria_xlsx_v1') and i.categorization_source='fallback'
   and i.duplicate_decision is distinct from 'skip' and e.source='fallback'
   and e.normalized_merchant=public.normalize_merchant(coalesce(nullif(i.merchant_name,''),i.raw_description))
   and length(public.normalize_merchant(coalesce(nullif(i.merchant_name,''),i.raw_description)))>=3
   and not exists(select 1 from public.ai_merchant_rules r where r.user_id=i.user_id and r.kind=i.transaction_type and r.merchant_key=e.normalized_merchant)
   and not exists(select 1 from public.ai_suggestions s where s.user_id=i.user_id and s.kind=i.transaction_type and s.merchant_key=e.normalized_merchant)
 group by i.transaction_type,public.normalize_merchant(coalesce(nullif(i.merchant_name,''),i.raw_description));
$$;
revoke all on function private.ai_candidates(uuid,uuid) from public,anon,authenticated;
create function public.ai_import_candidates(p_batch_id uuid)
returns table(group_id text, merchant text, kind text, item_count bigint)
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.import_batches where id=p_batch_id and user_id=(select auth.uid())) then raise exception 'Import not found' using errcode='42501'; end if;
 return query select * from private.ai_candidates((select auth.uid()),p_batch_id);
end;
$$;
revoke all on function public.ai_import_candidates(uuid) from public,anon,authenticated;
grant execute on function public.ai_import_candidates(uuid) to authenticated;

create function public.ai_reserve(p_user uuid,p_token uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 insert into private.ai_request_locks(user_id,token,expires_at) values(p_user,p_token,now()+interval '90 seconds')
 on conflict(user_id) do update set token=excluded.token,expires_at=excluded.expires_at where private.ai_request_locks.expires_at<now();
 return found;
end; $$;
create function public.ai_release(p_user uuid,p_token uuid) returns void language sql security definer set search_path='' as $$
 delete from private.ai_request_locks where user_id=p_user and token=p_token;
$$;
revoke all on function public.ai_reserve(uuid,uuid),public.ai_release(uuid,uuid) from public,anon,authenticated;
grant execute on function public.ai_reserve(uuid,uuid),public.ai_release(uuid,uuid) to service_role;

-- Persist only validated, still eligible results. Re-evaluation happens only in
-- the explicitly selected unconfirmed import; past transactions are not edited.
create function public.ai_store_results(p_user uuid,p_batch uuid,p_token uuid,p_results jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v jsonb; c record; v_category uuid; v_key text; v_count integer:=0; v_pending integer:=0; v_name text; v_batch_status text;
begin
 if not exists(select 1 from private.ai_request_locks where user_id=p_user and token=p_token and expires_at>now()) then raise exception 'Request expired'; end if;
 select status into v_batch_status from public.import_batches where id=p_batch and user_id=p_user for update;
 if v_batch_status not in ('ready','completed') then raise exception 'Import unavailable'; end if;
 if jsonb_typeof(p_results)<>'array' or jsonb_array_length(p_results)>10 then raise exception 'Invalid results'; end if;
 for v in select * from jsonb_array_elements(p_results) loop
   select * into c from private.ai_candidates(p_user,p_batch) where group_id=v->>'groupId';
   if not found then continue; end if;
   v_key:=public.normalize_merchant(c.merchant);
   v_name:=case v->>'category'
    when 'groceries' then 'Продукты' when 'restaurants' then 'Рестораны' when 'transport' then 'Транспорт'
    when 'taxi' then 'Такси' when 'automotive' then 'Автомобиль' when 'housing' then 'Жильё'
    when 'utilities' then 'Коммунальные услуги' when 'telecom' then 'Связь' when 'shopping' then 'Покупки'
    when 'entertainment' then 'Развлечения' when 'health' then 'Здоровье' when 'travel' then 'Путешествия'
    when 'salary' then 'Зарплата' else null end;
   select id into v_category from public.categories where user_id=p_user and kind=c.kind and name=v_name order by id limit 1;
   if v_category is null then continue; end if;
   if (v->>'confidence')::numeric>=(select high_confidence from private.ai_configuration where singleton) and (v->>'unambiguous')::boolean and v->>'reason'='clear' then
    insert into public.ai_merchant_rules(user_id,kind,merchant_key,merchant_name,category_id,confidence,model,prompt_version)
    values(p_user,c.kind,v_key,c.merchant,v_category,(v->>'confidence')::numeric,'gemini-4-hydrogen','merchant-category-v1') on conflict do nothing;
    if found then v_count:=v_count+1; end if;
   elsif (v->>'confidence')::numeric>=(select medium_confidence from private.ai_configuration where singleton) then
    insert into public.ai_suggestions(user_id,kind,merchant_key,merchant_name,category_id,confidence,model,prompt_version)
    values(p_user,c.kind,v_key,c.merchant,v_category,(v->>'confidence')::numeric,'gemini-4-hydrogen','merchant-category-v1') on conflict do nothing;
    if found then v_pending:=v_pending+1; end if;
   end if;
 end loop;
 if v_batch_status='ready' then
  update public.import_items set raw_data=raw_data where user_id=p_user and batch_id=p_batch and categorization_source='fallback';
 end if;
 return jsonb_build_object('rules',v_count,'suggestions',v_pending);
end; $$;
revoke all on function public.ai_store_results(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.ai_store_results(uuid,uuid,uuid,jsonb) to service_role;

create function public.ai_review_suggestion(p_id uuid,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$
declare s public.ai_suggestions%rowtype;
begin
 select * into s from public.ai_suggestions where id=p_id and user_id=(select auth.uid()) and status='pending' for update;
 if not found then raise exception 'Suggestion unavailable' using errcode='42501'; end if;
 if p_accept then
  insert into public.ai_merchant_rules(user_id,kind,merchant_key,merchant_name,category_id,confidence,model,prompt_version)
  values(s.user_id,s.kind,s.merchant_key,s.merchant_name,s.category_id,s.confidence,s.model,s.prompt_version) on conflict do nothing;
  delete from public.ai_suggestions where id=s.id;
 else update public.ai_suggestions set status='dismissed' where id=s.id; end if;
end; $$;
revoke all on function public.ai_review_suggestion(uuid,boolean) from public,anon,authenticated;
grant execute on function public.ai_review_suggestion(uuid,boolean) to authenticated;
-- A manual correction wins permanently over any conflicting AI mapping.
create function private.disable_corrected_ai_rule() returns trigger language plpgsql security definer set search_path='' as $$
declare v_key text; v_alias text;
begin
 if old.category_id is distinct from new.category_id then
  v_key:=public.normalize_merchant(coalesce(nullif(new.merchant_name,''),new.raw_description));
  select public.normalize_merchant(a.canonical_name) into v_alias from public.merchant_aliases a
   where a.user_id=new.user_id and a.kind=new.transaction_type and public.normalize_merchant(a.alias)=v_key limit 1;
  update public.ai_merchant_rules set enabled=false where user_id=new.user_id and kind=new.transaction_type
   and merchant_key=coalesce(v_alias,v_key) and category_id<>new.category_id;
 end if;
 return new;
end; $$;
create trigger transactions_disable_corrected_ai_rule after update of category_id on public.transactions
 for each row execute function private.disable_corrected_ai_rule();
-- If an AI rule is disabled or removed before confirmation, re-evaluation must
-- restore the default instead of retaining the previously suggested category.
create or replace function private.categorize_import_item() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_format text; v_result record; v_default uuid;
begin
 select format into v_format from public.import_batches where id=new.batch_id and user_id=new.user_id;
 if v_format='cashradar_csv_v1' then new.categorization_source:='manual'; return new; end if;
 new.merchant_name:=left(nullif(btrim(coalesce(new.raw_data->>'AD',new.raw_description,'')),''),500);
 if coalesce(new.raw_data->>'mcc','') ~ '^[0-9]{4}$' then new.mcc:=new.raw_data->>'mcc'; end if;
 v_default:=new.category_id;
 if tg_op='UPDATE' and old.categorization_source='ai' then
  select c.id into v_default from public.categories c where c.user_id=new.user_id and c.kind=new.transaction_type
   and c.name=case when new.transaction_type='income' then 'Прочие доходы' else 'Прочие расходы' end order by c.id limit 1;
  v_default:=coalesce(v_default,new.category_id);
 end if;
 select * into v_result from private.evaluate_category(new.user_id,new.transaction_type,new.merchant_name,new.mcc,v_default);
 new.category_id:=v_result.category_id; new.categorization_source:=v_result.source; new.normalized_merchant:=nullif(v_result.normalized_merchant,'');
 return new;
end;
$$;
