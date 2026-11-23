\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role) values
 ('fa000000-0000-4000-8000-000000000001','own-funds@example.test','authenticated','authenticated');
do $$
declare
  owner uuid := 'fa000000-0000-4000-8000-000000000001';
  result record;
  override_category uuid;
begin
  if (select count(*) from public.category_rules where user_id=owner and pattern='Transfer of own funds') <> 2 then
    raise exception 'Default rules were not created for both directions';
  end if;
  for result in
    select k.kind, e.category_id, e.source from (values ('income'),('expense')) k(kind)
    cross join lateral private.evaluate_category(owner,k.kind,'Transfer of own funds լրացուցիչ',null,null) e
  loop
    if result.source <> 'rule' or not exists (
      select 1 from public.categories where id=result.category_id and user_id=owner
        and kind=result.kind and name='Перевод собственных средств'
    ) then raise exception 'Own funds category not applied for %', result.kind; end if;
  end loop;
  select id into override_category from public.categories where user_id=owner and name='Покупки' and kind='expense';
  insert into public.category_rules(user_id,kind,match_type,pattern,category_id,priority)
  values(owner,'expense','merchant_contains','transfer of own funds',override_category,100);
  select * into result from private.evaluate_category(owner,'expense','Transfer of own funds',null,null);
  if result.category_id <> override_category then raise exception 'Custom rule did not take priority'; end if;
end $$;
rollback;
