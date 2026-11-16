\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role) values
 ('98000000-0000-4000-8000-000000000001','transfer-a@example.test','authenticated','authenticated'),
 ('98000000-0000-4000-8000-000000000002','transfer-b@example.test','authenticated','authenticated');
insert into public.accounts(id,user_id,name,account_type,currency,initial_balance) values
 ('98100000-0000-4000-8000-000000000001','98000000-0000-4000-8000-000000000001','Bank A','cash','AMD',1000),
 ('98100000-0000-4000-8000-000000000002','98000000-0000-4000-8000-000000000001','Wallet','cash','AMD',0),
 ('98100000-0000-4000-8000-000000000003','98000000-0000-4000-8000-000000000001','USD','cash','USD',0),
 ('98100000-0000-4000-8000-000000000004','98000000-0000-4000-8000-000000000002','Other','cash','AMD',0);
select set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select set_config('test.group',public.create_manual_transfer('98100000-0000-4000-8000-000000000001','98100000-0000-4000-8000-000000000002','2026-11-01',100,100,2,'Synthetic movement','98200000-0000-4000-8000-000000000001')::text,true);
do $$ declare again uuid; begin
 again:=public.create_manual_transfer('98100000-0000-4000-8000-000000000001','98100000-0000-4000-8000-000000000002','2026-11-01',100,100,2,'Synthetic movement','98200000-0000-4000-8000-000000000001');
 if again<>current_setting('test.group')::uuid or (select count(*) from public.transactions)<>3 then raise exception 'request repeated the transfer'; end if;
 begin perform public.create_manual_transfer('98100000-0000-4000-8000-000000000001','98100000-0000-4000-8000-000000000002','2026-11-01',200,200,2,'Synthetic movement','98200000-0000-4000-8000-000000000001'); raise exception 'changed request accepted'; exception when invalid_parameter_value then null; end;
end $$;
do $$ declare a numeric; b numeric; begin
 select current_balance::numeric into a from public.account_balances where id='98100000-0000-4000-8000-000000000001';
 select current_balance::numeric into b from public.account_balances where id='98100000-0000-4000-8000-000000000002';
 if a<>898 or b<>100 then raise exception 'incorrect balances: %, %',a,b; end if;
 if (select count(*) from public.income_expense_transactions)<>1 then raise exception 'transfer counted as income/expense or fee missing'; end if;
 if (select count(*) from public.transfer_group_details where id=current_setting('test.group')::uuid and fee_amount='2')<>1 then raise exception 'fee not linked'; end if;
 begin update public.transactions set amount=50 where id=(select debit_id from public.transfer_groups where id=current_setting('test.group')::uuid); raise exception 'linked operation edited'; exception when check_violation then null; end;
 begin delete from public.transactions where id=(select credit_id from public.transfer_groups where id=current_setting('test.group')::uuid); raise exception 'linked operation deleted'; exception when check_violation then null; end;
 begin perform public.create_manual_transfer('98100000-0000-4000-8000-000000000001','98100000-0000-4000-8000-000000000004','2026-11-01',20,20,0,null,'98200000-0000-4000-8000-000000000002'); raise exception 'foreign account accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.create_manual_transfer('98100000-0000-4000-8000-000000000001','98100000-0000-4000-8000-000000000002','2026-11-01',20,19,0,null,'98200000-0000-4000-8000-000000000003'); raise exception 'hidden fee accepted'; exception when invalid_parameter_value then null; end;
end $$;
select set_config('test.fx',public.create_manual_transfer('98100000-0000-4000-8000-000000000001','98100000-0000-4000-8000-000000000003','2026-11-02',400,1,0,null,'98200000-0000-4000-8000-000000000004')::text,true);
do $$ begin
 if not exists(select 1 from public.transfer_group_details where id=current_setting('test.fx')::uuid and debit_amount='400' and credit_amount='1' and debit_currency='AMD' and credit_currency='USD') then raise exception 'FX actual values lost'; end if;
end $$;
select set_config('test.debit',(select debit_id::text from public.transfer_groups where id=current_setting('test.group')::uuid),true);
select public.unlink_transfer(current_setting('test.group')::uuid);
do $$ begin
 if (select count(*) from public.income_expense_transactions)<>3 then raise exception 'unlink should retain all postings'; end if;
 if not exists(select 1 from public.transfer_candidates where debit_id=current_setting('test.debit')::uuid) then raise exception 'candidate missing'; end if;
end $$;
select set_config('test.credit',(select credit_id::text from public.transfer_candidates where debit_id=current_setting('test.debit')::uuid and credit_account='Wallet' limit 1),true);
do $$ begin
 begin
  perform public.confirm_transfer(current_setting('test.debit')::uuid,current_setting('test.credit')::uuid,null,now()-interval '1 day',now(),null);
  raise exception 'stale candidate was linked';
 exception when serialization_failure then null; end;
end $$;
select public.reject_transfer_candidate(current_setting('test.debit')::uuid,current_setting('test.credit')::uuid);
do $$ begin
 if exists(select 1 from public.transfer_candidates where debit_id=current_setting('test.debit')::uuid and credit_id=current_setting('test.credit')::uuid) then raise exception 'rejected pair returned'; end if;
end $$;
update public.transactions set raw_description='Updated synthetic movement' where id=current_setting('test.debit')::uuid;
do $$ begin
 if not exists(select 1 from public.transfer_candidates where debit_id=current_setting('test.debit')::uuid and credit_id=current_setting('test.credit')::uuid) then raise exception 'changed candidate did not return'; end if;
end $$;
insert into public.transactions(account_id,category_id,transaction_type,transaction_date,amount,currency,account_amount,account_currency,raw_description)
select '98100000-0000-4000-8000-000000000001',id,'expense','2026-11-08',25,'AMD',25,'AMD','Synthetic cash withdrawal'
from public.categories where user_id=(select auth.uid()) and kind='expense' order by id limit 1;
select set_config('test.cashdebit',(select id::text from public.transactions where raw_description='Synthetic cash withdrawal'),true);
do $$ begin
 begin
  perform public.transfer_to_cash(current_setting('test.cashdebit')::uuid,'98100000-0000-4000-8000-000000000002',now()-interval '1 day');
  raise exception 'stale withdrawal was accepted';
 exception when serialization_failure then null; end;
end $$;
select set_config('test.cashgroup',public.transfer_to_cash(current_setting('test.cashdebit')::uuid,'98100000-0000-4000-8000-000000000002')::text,true);
do $$ begin
 if (select current_balance::numeric from public.account_balances where id='98100000-0000-4000-8000-000000000002')<>125 then raise exception 'cash withdrawal balance wrong'; end if;
 if not exists(select 1 from public.transfer_group_details where id=current_setting('test.cashgroup')::uuid and credit_amount='25') then raise exception 'cash transfer missing'; end if;
 begin perform public.transfer_to_cash(current_setting('test.cashdebit')::uuid,'98100000-0000-4000-8000-000000000002'); raise exception 'withdrawal repeated'; exception when unique_violation then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ begin
 if exists(select 1 from public.transfer_groups) or exists(select 1 from public.transfer_candidates) then raise exception 'foreign transfer visible'; end if;
 begin perform public.unlink_transfer(current_setting('test.fx')::uuid); raise exception 'foreign transfer unlinked'; exception when insufficient_privilege then null; end;
end $$;
reset role;
delete from auth.users where id='98000000-0000-4000-8000-000000000001';
do $$ begin
 if exists(select 1 from public.transfer_groups where user_id='98000000-0000-4000-8000-000000000001') then raise exception 'user deletion left transfers'; end if;
end $$;
rollback;
