-- A valid uncertain/unknown answer is remembered, so it isn't sent repeatedly.
-- The owner can forget a result and deliberately retry after a model change.
create table public.ai_unrecognized_merchants (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('expense','income')),
 merchant_key text not null check(length(merchant_key) between 3 and 500),
 merchant_name text not null check(length(merchant_name) between 3 and 80),
 model text not null check(model in ('gemini-4-hydrogen','gemini-3.8-flash')),
 prompt_version text not null, created_at timestamptz not null default now(),
 unique(user_id,kind,merchant_key)
);
alter table public.ai_unrecognized_merchants enable row level security;
revoke all on public.ai_unrecognized_merchants from public,anon,authenticated;
grant select,delete on public.ai_unrecognized_merchants to authenticated;
grant all on public.ai_unrecognized_merchants to service_role;
create policy ai_unrecognized_read on public.ai_unrecognized_merchants for select to authenticated using(user_id=(select auth.uid()));
create policy ai_unrecognized_delete on public.ai_unrecognized_merchants for delete to authenticated using(user_id=(select auth.uid()));

create or replace function private.ai_candidates(p_user uuid,p_batch uuid)
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
   and not exists(select 1 from public.ai_unrecognized_merchants u where u.user_id=i.user_id and u.kind=i.transaction_type and u.merchant_key=e.normalized_merchant)
   and not exists(select 1 from public.ai_suggestions s where s.user_id=i.user_id and s.kind=i.transaction_type and s.merchant_key=e.normalized_merchant)
 group by i.transaction_type,public.normalize_merchant(coalesce(nullif(i.merchant_name,''),i.raw_description))
 order by min(coalesce(nullif(i.merchant_name,''),i.raw_description)),i.transaction_type;
$$;

drop function public.ai_store_results(uuid,uuid,uuid,jsonb);
create function public.ai_store_results(p_user uuid,p_batch uuid,p_token uuid,p_results jsonb,p_model text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v jsonb; c record; v_category uuid; v_key text; v_count integer:=0; v_pending integer:=0; v_unknown integer:=0; v_missing integer:=0; v_name text; v_batch_status text;
begin
 if not exists(select 1 from private.ai_request_locks where user_id=p_user and token=p_token and expires_at>now()) then raise exception 'Request expired'; end if;
 select status into v_batch_status from public.import_batches where id=p_batch and user_id=p_user for update;
 if v_batch_status not in ('ready','completed') then raise exception 'Import unavailable'; end if;
 if p_model not in ('gemini-4-hydrogen','gemini-3.8-flash') then raise exception 'Invalid model'; end if;
 if jsonb_typeof(p_results)<>'array' or jsonb_array_length(p_results)>10 then raise exception 'Invalid results'; end if;
 for v in select * from jsonb_array_elements(p_results) loop
   select * into c from private.ai_candidates(p_user,p_batch) where group_id=v->>'groupId';
   if not found then continue; end if;
   v_key:=public.normalize_merchant(c.merchant);
   if v->>'category' in ('unknown','other') or v->>'reason'='unknown'
      or (v->>'confidence')::numeric<(select medium_confidence from private.ai_configuration where singleton) then
    insert into public.ai_unrecognized_merchants(user_id,kind,merchant_key,merchant_name,model,prompt_version)
     values(p_user,c.kind,v_key,c.merchant,p_model,'merchant-category-v1') on conflict do nothing;
    if found then v_unknown:=v_unknown+1; end if;
    continue;
   end if;
   v_name:=case v->>'category'
    when 'groceries' then 'Продукты' when 'restaurants' then 'Рестораны' when 'transport' then 'Транспорт'
    when 'taxi' then 'Такси' when 'automotive' then 'Автомобиль' when 'housing' then 'Жильё'
    when 'utilities' then 'Коммунальные услуги' when 'telecom' then 'Связь' when 'shopping' then 'Покупки'
    when 'entertainment' then 'Развлечения' when 'health' then 'Здоровье' when 'travel' then 'Путешествия'
    when 'salary' then 'Зарплата' else null end;
   select id into v_category from public.categories where user_id=p_user and kind=c.kind and name=v_name order by id limit 1;
   if v_category is null then v_missing:=v_missing+1; continue; end if;
   if (v->>'confidence')::numeric>=(select high_confidence from private.ai_configuration where singleton) and (v->>'unambiguous')::boolean and v->>'reason'='clear' then
    insert into public.ai_merchant_rules(user_id,kind,merchant_key,merchant_name,category_id,confidence,model,prompt_version)
    values(p_user,c.kind,v_key,c.merchant,v_category,(v->>'confidence')::numeric,p_model,'merchant-category-v1') on conflict do nothing;
    if found then v_count:=v_count+1; end if;
   elsif (v->>'confidence')::numeric>=(select medium_confidence from private.ai_configuration where singleton) then
    insert into public.ai_suggestions(user_id,kind,merchant_key,merchant_name,category_id,confidence,model,prompt_version)
    values(p_user,c.kind,v_key,c.merchant,v_category,(v->>'confidence')::numeric,p_model,'merchant-category-v1') on conflict do nothing;
    if found then v_pending:=v_pending+1; end if;
   end if;
 end loop;
 if v_batch_status='ready' then
  update public.import_items set raw_data=raw_data where user_id=p_user and batch_id=p_batch and categorization_source='fallback';
 end if;
 return jsonb_build_object('rules',v_count,'suggestions',v_pending,'unrecognized',v_unknown,'missing_categories',v_missing);
end; $$;
revoke all on function public.ai_store_results(uuid,uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.ai_store_results(uuid,uuid,uuid,jsonb,text) to service_role;
