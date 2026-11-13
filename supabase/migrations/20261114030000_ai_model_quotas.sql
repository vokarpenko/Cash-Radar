-- Limits are shared by the provider project, not by a browser session.
create table private.ai_model_quotas (
 model text primary key check(model in ('gemini-4-hydrogen','gemini-3.8-flash','gemini-3.6-flash','gemini-3.5-flash-lite')),
 cooldown_until timestamptz not null default '-infinity',
 next_request_at timestamptz not null default '-infinity'
);
insert into private.ai_model_quotas(model) values
 ('gemini-4-hydrogen'),('gemini-3.8-flash'),('gemini-3.6-flash'),('gemini-3.5-flash-lite');
revoke all on private.ai_model_quotas from public,anon,authenticated;

-- -1 means paused; zero reserves a slot now; a positive value is a wait in ms.
create function public.ai_claim_model(p_model text) returns integer language plpgsql security definer set search_path='' as $$
declare q private.ai_model_quotas%rowtype; v_now timestamptz:=clock_timestamp(); v_delay integer;
begin
 select * into q from private.ai_model_quotas where model=p_model for update;
 if not found then raise exception 'Invalid model'; end if;
 if q.cooldown_until>v_now then return -1; end if;
 if q.next_request_at>v_now then return ceil(extract(epoch from q.next_request_at-v_now)*1000)::integer; end if;
 v_delay:=case when p_model='gemini-3.5-flash-lite' then 4 else 13 end;
 update private.ai_model_quotas set next_request_at=v_now+make_interval(secs=>v_delay) where model=p_model;
 return 0;
end; $$;
create function public.ai_pause_model(p_model text) returns void language plpgsql security definer set search_path='' as $$
begin
 update private.ai_model_quotas set cooldown_until=greatest(cooldown_until,clock_timestamp()+interval '1 hour') where model=p_model;
 if not found then raise exception 'Invalid model'; end if;
end; $$;
revoke all on function public.ai_claim_model(text),public.ai_pause_model(text) from public,anon,authenticated;
grant execute on function public.ai_claim_model(text),public.ai_pause_model(text) to service_role;

alter table public.ai_unrecognized_merchants drop constraint ai_unrecognized_merchants_model_check;
alter table public.ai_unrecognized_merchants add constraint ai_unrecognized_merchants_model_check check(model in ('gemini-4-hydrogen','gemini-3.8-flash','gemini-3.6-flash','gemini-3.5-flash-lite'));

create or replace function public.ai_store_results(p_user uuid,p_batch uuid,p_token uuid,p_results jsonb,p_model text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v jsonb; c record; v_category uuid; v_key text; v_count integer:=0; v_pending integer:=0; v_unknown integer:=0; v_missing integer:=0; v_name text; v_batch_status text;
begin
 if not exists(select 1 from private.ai_request_locks where user_id=p_user and token=p_token and expires_at>now()) then raise exception 'Request expired'; end if;
 select status into v_batch_status from public.import_batches where id=p_batch and user_id=p_user for update;
 if v_batch_status not in ('ready','completed') then raise exception 'Import unavailable'; end if;
 if p_model not in ('gemini-4-hydrogen','gemini-3.8-flash','gemini-3.6-flash','gemini-3.5-flash-lite') then raise exception 'Invalid model'; end if;
 if jsonb_typeof(p_results)<>'array' or jsonb_array_length(p_results)>25 then raise exception 'Invalid results'; end if;
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
create or replace function public.ai_reserve(p_user uuid,p_token uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 insert into private.ai_request_locks(user_id,token,expires_at) values(p_user,p_token,now()+interval '180 seconds')
 on conflict(user_id) do update set token=excluded.token,expires_at=excluded.expires_at where private.ai_request_locks.expires_at<now();
 return found;
end; $$;
