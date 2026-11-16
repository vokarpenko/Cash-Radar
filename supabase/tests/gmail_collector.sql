\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role) values
 ('83000000-0000-4000-8000-000000000001','collector-a@example.test','authenticated','authenticated'),
 ('83000000-0000-4000-8000-000000000002','collector-b@example.test','authenticated','authenticated');
insert into public.accounts(id,user_id,name,account_type,currency,initial_balance,bank_id) values
 ('83000000-0000-4000-8000-000000000003','83000000-0000-4000-8000-000000000001','Synthetic','bank','RUB',0,(select id from public.banks where code='alfa_ru')),
 ('83000000-0000-4000-8000-000000000004','83000000-0000-4000-8000-000000000001','Other','bank','RUB',0,(select id from public.banks where code='alfa_ru'));
do $$ declare u uuid:='83000000-0000-4000-8000-000000000001'; a uuid:='83000000-0000-4000-8000-000000000003'; lease uuid:='83000000-0000-4000-8000-000000000005'; other uuid:='83000000-0000-4000-8000-000000000006'; begin
 if has_function_privilege('authenticated','public.gmail_claim_attachment(uuid,uuid,text,text,uuid)','execute') or has_table_privilege('authenticated','public.gmail_poll_cursors','select') or has_column_privilege('authenticated','public.gmail_import_jobs','message_id','select') then raise exception 'Collector privilege leak'; end if;
 if public.gmail_claim_attachment(u,a,'message_long',repeat('x',404),lease)<>'claimed' then raise exception 'Long Gmail attachment id rejected'; end if;
 delete from public.gmail_import_jobs where user_id=u and message_id='message_long';
 if public.gmail_claim_attachment(u,a,'message_a','attachment_a',lease)<>'claimed' then raise exception 'Claim failed'; end if;
 if public.gmail_claim_attachment(u,a,'message_a','attachment_a',other)<>'busy' then raise exception 'Lease not exclusive'; end if;
 if public.gmail_claim_attachment(u,'83000000-0000-4000-8000-000000000004','message_a','attachment_a',other)<>'wrong_account' then raise exception 'Wrong account allowed'; end if;
 if public.gmail_finish_attachment(u,'message_a','attachment_a',other,null,'import_failed') then raise exception 'Wrong lease finished task'; end if;
 if not public.gmail_finish_attachment(u,'message_a','attachment_a',lease,null,'import_failed') then raise exception 'Failure not saved'; end if;
 if public.gmail_claim_attachment(u,a,'message_a','attachment_a',other)<>'busy' then raise exception 'Failure cooldown skipped'; end if;
 update public.gmail_import_jobs set updated_at=now()-interval '2 minutes' where user_id=u;
 if public.gmail_claim_attachment(u,a,'message_a','attachment_a',other)<>'claimed' then raise exception 'Retry unavailable'; end if;
 update public.gmail_import_jobs set lease_until=now()-interval '1 second' where user_id=u;
 if public.gmail_finish_attachment(u,'message_a','attachment_a',other,null,'import_failed') then raise exception 'Expired lease accepted'; end if;
 if public.gmail_claim_attachment(u,a,'message_long',repeat('x',404),lease)<>'claimed' then raise exception 'Long Gmail attachment id rejected'; end if;
 delete from public.gmail_import_jobs where user_id=u and message_id='message_long';
 if public.gmail_claim_attachment(u,a,'message_a','attachment_a',lease)<>'claimed' then raise exception 'Expired lease not recovered'; end if;
end $$;
insert into public.gmail_collector_runs(user_id,scanned,error_code) values('83000000-0000-4000-8000-000000000001',1,'authorization_expired');
select set_config('request.jwt.claims','{"sub":"83000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin if exists(select id from public.gmail_import_jobs) or exists(select id from public.gmail_collector_runs) then raise exception 'Another user sees jobs or run logs'; end if; end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"83000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ begin if (select count(id) from public.gmail_import_jobs)<>1 or (select count(id) from public.gmail_collector_runs)<>1 then raise exception 'Owner cannot see job or run log'; end if; end $$;
rollback;
