\set ON_ERROR_STOP on
begin;
update private.ai_model_quotas set cooldown_until='-infinity',next_request_at='-infinity';
do $$ declare n integer; begin
 if public.ai_claim_model('gemini-3.6-flash')<>0 then raise exception 'first claim failed'; end if;
 n:=public.ai_claim_model('gemini-3.6-flash');
 if n<12000 or n>13000 then raise exception 'upper model spacing invalid: %',n; end if;
 if public.ai_claim_model('gemini-3.5-flash-lite')<>0 then raise exception 'lite claim failed'; end if;
 n:=public.ai_claim_model('gemini-3.5-flash-lite');
 if n<3000 or n>4000 then raise exception 'lite spacing invalid: %',n; end if;
 perform public.ai_pause_model('gemini-3.6-flash');
 if public.ai_claim_model('gemini-3.6-flash')<>-1 then raise exception 'paused model is not skipped'; end if;
 if (select cooldown_until from private.ai_model_quotas where model='gemini-3.6-flash') < clock_timestamp()+interval '59 minutes' then raise exception 'cooldown too short'; end if;
end $$;
set local role authenticated;
do $$ begin
 begin perform public.ai_claim_model('gemini-3.6-flash'); raise exception 'client could claim model'; exception when insufficient_privilege then null; end;
 begin perform public.ai_pause_model('gemini-3.6-flash'); raise exception 'client could pause model'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
