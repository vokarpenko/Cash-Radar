\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role) values ('97000000-0000-4000-8000-000000000001','delivery-test@example.test','authenticated','authenticated');
select set_config('test.user','97000000-0000-4000-8000-000000000001',true),
 set_config('test.default',(select id::text from public.categories where user_id='97000000-0000-4000-8000-000000000001' and name='Прочие расходы'),true),
 set_config('test.restaurant',(select id::text from public.categories where user_id='97000000-0000-4000-8000-000000000001' and name='Рестораны'),true);
do $$ declare r record; begin
 if not exists(select 1 from public.categories where user_id=current_setting('test.user')::uuid and name='Доставка еды' and kind='expense') then raise exception 'default missing'; end if;
 select * into r from private.evaluate_category(current_setting('test.user')::uuid,'expense','Ք: Glovo BARCELONA 123456 Bank',null,current_setting('test.default')::uuid);
 if r.source<>'delivery' or not exists(select 1 from public.categories where id=r.category_id and name='Доставка еды') then raise exception 'Ameria Glovo not recognised'; end if;
 select * into r from private.evaluate_category(current_setting('test.user')::uuid,'expense','Yandex Eda',null,current_setting('test.default')::uuid);
 if r.source<>'delivery' then raise exception 'Yandex Eda not recognised'; end if;
 select * into r from private.evaluate_category(current_setting('test.user')::uuid,'expense','Яндекс Такси',null,current_setting('test.default')::uuid);
 if r.source<>'fallback' then raise exception 'taxi incorrectly classified as food delivery'; end if;
 select * into r from private.evaluate_category(current_setting('test.user')::uuid,'expense','Not Glovo',null,current_setting('test.default')::uuid);
 if r.source<>'fallback' then raise exception 'unrelated merchant incorrectly classified'; end if;
 select * into r from private.evaluate_category(current_setting('test.user')::uuid,'income','Glovo',null,null);
 if r.source<>'fallback' then raise exception 'income incorrectly classified as delivery expense'; end if;
end $$;
insert into public.category_rules(user_id,kind,match_type,pattern,category_id,priority) values(current_setting('test.user')::uuid,'expense','merchant_contains','glovo',current_setting('test.restaurant')::uuid,100);
do $$ declare r record; begin
 select * into r from private.evaluate_category(current_setting('test.user')::uuid,'expense','Ք: Glovo BARCELONA 123456 Bank',null,current_setting('test.default')::uuid);
 if r.source<>'rule' or r.category_id<>current_setting('test.restaurant')::uuid then raise exception 'owner rule did not override delivery default'; end if;
end $$;
rollback;
