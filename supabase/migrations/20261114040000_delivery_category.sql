-- A service name alone does not identify the contents of an order. Keep such
-- spending separately unless the owner has a more specific rule or correction.
insert into public.categories(user_id,name,kind)
select u.id,'Доставка еды','expense' from auth.users u
where not exists(select 1 from public.categories c where c.user_id=u.id and c.kind='expense' and c.name='Доставка еды');

create or replace function private.create_user_defaults(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (p_user_id);
  insert into public.categories (user_id, name, kind) values
    (p_user_id, 'Продукты', 'expense'),
    (p_user_id, 'Рестораны', 'expense'),
    (p_user_id, 'Доставка еды', 'expense'),
    (p_user_id, 'Транспорт', 'expense'),
    (p_user_id, 'Такси', 'expense'),
    (p_user_id, 'Автомобиль', 'expense'),
    (p_user_id, 'Жильё', 'expense'),
    (p_user_id, 'Коммунальные услуги', 'expense'),
    (p_user_id, 'Связь', 'expense'),
    (p_user_id, 'Покупки', 'expense'),
    (p_user_id, 'Развлечения', 'expense'),
    (p_user_id, 'Здоровье', 'expense'),
    (p_user_id, 'Путешествия', 'expense'),
    (p_user_id, 'Зарплата', 'income'),
    (p_user_id, 'Переводы', 'transfer'),
    (p_user_id, 'Прочие доходы', 'income'),
    (p_user_id, 'Прочие расходы', 'expense');
end;
$$;


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
 -- Recognise only explicit food-delivery brands, not generic Yandex services.
 if p_kind='expense' and coalesce(v_canonical,v_key) ~ '^(ք )?(glovo|yandex (eats|eda|food)|яндекс (еда|доставка еды))( |$)' then
  select c.id into v_category from public.categories c where c.user_id=p_user and c.kind='expense' and c.name='Доставка еды' order by c.parent_id nulls first,c.id limit 1;
  if found then return query select v_category,'delivery'::text,coalesce(v_canonical,v_key); return; end if;
 end if;
 return query select p_default,'fallback'::text,coalesce(v_canonical,v_key);
end;
$$;
alter table public.import_items drop constraint import_items_categorization_source_check;
alter table public.import_items add constraint import_items_categorization_source_check check(categorization_source in ('manual','rule','alias','mcc','history','fallback','ai','delivery'));
alter table public.transactions drop constraint transactions_categorization_source_check;
alter table public.transactions add constraint transactions_categorization_source_check check(categorization_source in ('manual','rule','alias','mcc','history','fallback','ai','delivery'));
