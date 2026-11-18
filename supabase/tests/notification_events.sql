\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role) values
 ('84000000-0000-4000-8000-000000000001','notification-a@example.test','authenticated','authenticated'),
 ('84000000-0000-4000-8000-000000000002','notification-b@example.test','authenticated','authenticated');
insert into public.accounts(id,user_id,name,account_type,currency,initial_balance) values
 ('84000000-0000-4000-8000-000000000003','84000000-0000-4000-8000-000000000001','Synthetic','cash','AMD',100);
select set_config('request.jwt.claims','{"sub":"84000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare d jsonb; begin
 d:=public.register_notification_device();
 perform set_config('test.notification.token',d->>'device_token',true);
 perform set_config('test.notification.device',d->>'device_id',true);
 d:=public.register_notification_device();
 perform set_config('test.notification.second_token',d->>'device_token',true);
 if (d->>'device_token') !~ '^[0-9a-f]{64}$' then raise exception 'Bad device token'; end if;
 if has_column_privilege('authenticated','public.notification_devices','token_hash','select') then raise exception 'Device hash exposed'; end if;
end $$;
reset role;
do $$ declare p jsonb:=jsonb_build_object('event_key',repeat('a',64),'source','acba','kind','pre_purchase','amount','100.25','currency','AMD','merchant','Synthetic Shop','card_last4','1111','occurred_at',now()::text,'time_source','bank'); r jsonb; begin
 r:=public.ingest_notification_event(current_setting('test.notification.token'),p);
 if (r->>'duplicate')::boolean then raise exception 'First event treated as duplicate'; end if;
 if not (public.ingest_notification_event(current_setting('test.notification.token'),p)->>'duplicate')::boolean then raise exception 'Duplicate was not detected'; end if;
 if not (public.ingest_notification_event(current_setting('test.notification.second_token'),p)->>'duplicate')::boolean then raise exception 'Retry after device replacement duplicated data'; end if;
 perform public.ingest_notification_event(current_setting('test.notification.token'),jsonb_set(p,'{event_key}',to_jsonb(repeat('b',64))));
 perform public.ingest_notification_event(current_setting('test.notification.token'),p || jsonb_build_object('event_key',repeat('c',64),'source','ameria'));
 if (select count(*) from public.notification_events where user_id='84000000-0000-4000-8000-000000000001')<>3 then raise exception 'Different transactions collapsed'; end if;
 begin perform public.ingest_notification_event(current_setting('test.notification.token'),p || '{"raw_text":"secret"}'::jsonb); raise exception 'Raw text accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.ingest_notification_event(current_setting('test.notification.token'),jsonb_set(p,'{merchant}',to_jsonb('OTP 123456'::text))); raise exception 'OTP accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.ingest_notification_event(current_setting('test.notification.token'),jsonb_set(p,'{merchant}',to_jsonb('CODE 123456'::text))); raise exception 'Code accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.ingest_notification_event(current_setting('test.notification.token'),jsonb_set(p,'{merchant}',to_jsonb('1234 5678 9012 3456'::text))); raise exception 'Full card accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.ingest_notification_event(current_setting('test.notification.token'),jsonb_set(p,'{source}',to_jsonb('sms'::text))); raise exception 'SMS accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.ingest_notification_event(repeat('0',64),p); raise exception 'Bad token accepted'; exception when insufficient_privilege then null; end;
 if (select current_balance::numeric from public.account_balances where id='84000000-0000-4000-8000-000000000003')<>100 then raise exception 'Pending affected balance'; end if;
 if exists(select 1 from public.transactions where user_id='84000000-0000-4000-8000-000000000001') then raise exception 'Pending created a confirmed transaction'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"84000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.notification_events) or exists(select id from public.notification_devices) then raise exception 'Foreign notifications visible'; end if;
 if public.revoke_notification_device(current_setting('test.notification.device')::uuid) then raise exception 'Foreign device revoked'; end if;
 if public.revoke_all_notification_devices()<>0 then raise exception 'Foreign devices revoked'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"84000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if (select count(*) from public.notification_events)<>3 then raise exception 'Owner cannot view events'; end if;
 if public.revoke_all_notification_devices()<>2 then raise exception 'Devices not revoked'; end if;
end $$;
reset role;
do $$ begin
 begin perform public.ingest_notification_event(current_setting('test.notification.token'),'{}'::jsonb); raise exception 'Invalid body accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.ingest_notification_event(current_setting('test.notification.token'),jsonb_build_object('event_key',repeat('c',64),'source','wallet','kind','purchase','amount','1','currency','AMD','merchant','Test Shop','card_last4','1111','occurred_at',now()::text,'time_source','notification')); raise exception 'Revoked device accepted'; exception when insufficient_privilege then null; end;
end $$;
rollback;
