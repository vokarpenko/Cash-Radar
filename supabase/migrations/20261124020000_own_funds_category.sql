-- Default categories are separate for income and expense because imported rows
-- carry one direction. Matching and pairing two legs remains a separate step.
insert into public.categories(user_id,name,kind)
select u.id,'Перевод собственных средств',k.kind
from auth.users u cross join (values ('expense'),('income')) as k(kind)
where not exists (
  select 1 from public.categories c
  where c.user_id=u.id and c.kind=k.kind and c.name='Перевод собственных средств'
);

insert into public.category_rules(user_id,kind,match_type,pattern,category_id,priority)
select u.id,k.kind,'merchant_contains','Transfer of own funds',c.id,0
from auth.users u cross join (values ('expense'),('income')) as k(kind)
cross join lateral (
  select id from public.categories c where c.user_id=u.id and c.kind=k.kind
    and c.name='Перевод собственных средств' order by c.created_at,c.id limit 1
) c
where not exists (
  select 1 from public.category_rules r where r.user_id=u.id and r.kind=k.kind
    and r.match_type='merchant_contains'
    and public.normalize_merchant(r.pattern)='transfer of own funds'
);

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
    (p_user_id, 'Перевод собственных средств', 'expense'),
    (p_user_id, 'Перевод собственных средств', 'income'),
    (p_user_id, 'Прочие доходы', 'income'),
    (p_user_id, 'Прочие расходы', 'expense');
  insert into public.category_rules(user_id,kind,match_type,pattern,category_id,priority)
  select p_user_id,c.kind,'merchant_contains','Transfer of own funds',c.id,0
  from public.categories c
  where c.user_id=p_user_id and c.name='Перевод собственных средств'
    and c.kind in ('expense','income');
end;
$$;
