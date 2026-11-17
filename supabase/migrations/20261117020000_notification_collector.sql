-- Device credentials never grant access to user data; they only submit strictly
-- validated notification summaries. Raw notifications and authentication codes
-- must not be sent to the server.
create table public.notification_devices (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 token_hash text not null unique check(token_hash ~ '^[0-9a-f]{64}$'),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default (now()+interval '90 days'),
 revoked_at timestamptz,
 unique(user_id,id)
);
alter table public.notification_devices enable row level security;
revoke all on public.notification_devices from public,anon,authenticated;
grant select (id,user_id,created_at,expires_at,revoked_at) on public.notification_devices to authenticated;
grant all on public.notification_devices to service_role;
create policy notification_devices_owner on public.notification_devices for select to authenticated using (user_id=(select auth.uid()));

create table public.notification_events (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 device_id uuid not null,
 event_key text not null check(event_key ~ '^[0-9a-f]{64}$'),
 source text not null check(source in ('wallet','ameria','acba')),
 kind text not null check(kind in ('purchase','credit','pre_purchase','pre_purchase_completion')),
 amount numeric not null check(amount>0 and amount<1e18 and amount=trunc(amount,2)),
 currency text not null check(currency in ('AMD','RUB','USD','EUR')),
 merchant text not null check(length(merchant) between 2 and 120),
 card_last4 text not null check(card_last4 ~ '^[0-9]{4}$'),
 occurred_at timestamptz not null,
 time_source text not null check(time_source in ('bank','notification')),
 created_at timestamptz not null default now(),
 dismissed_at timestamptz,
 unique(user_id,event_key),
 foreign key(user_id,device_id) references public.notification_devices(user_id,id)
);
create index notification_events_owner_created on public.notification_events(user_id,created_at desc);
create index notification_events_device_created on public.notification_events(device_id,created_at desc);
alter table public.notification_events enable row level security;
revoke all on public.notification_events from public,anon,authenticated;
grant select on public.notification_events to authenticated;
grant all on public.notification_events to service_role;
create policy notification_events_owner on public.notification_events for select to authenticated using (user_id=(select auth.uid()));

create view public.notification_event_details with (security_invoker=true) as
select id,user_id,source,kind,amount::text as amount,currency,merchant,card_last4,occurred_at,time_source,created_at,dismissed_at
from public.notification_events;
revoke all on public.notification_event_details from public,anon,authenticated;
grant select on public.notification_event_details to authenticated;
grant all on public.notification_event_details to service_role;

create function public.register_notification_device() returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=(select auth.uid()); token text; new_id uuid; expiry timestamptz;
begin
 if u is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if (select count(*) from public.notification_devices where user_id=u and revoked_at is null and expires_at>now()) >= 10 then raise exception 'Device limit reached' using errcode='22023'; end if;
 token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.notification_devices(user_id,token_hash) values(u,encode(extensions.digest(token,'sha256'),'hex')) returning id,expires_at into new_id,expiry;
 return jsonb_build_object('device_id',new_id,'device_token',token,'expires_at',expiry);
end $$;
create function public.revoke_notification_device(p_device uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if (select auth.uid()) is null then raise exception 'Authentication required' using errcode='42501'; end if;
 update public.notification_devices set revoked_at=now() where id=p_device and user_id=(select auth.uid()) and revoked_at is null;
 return found;
end $$;

create function public.revoke_all_notification_devices() returns integer
language plpgsql security definer set search_path='' as $$
declare affected integer;
begin
 if (select auth.uid()) is null then raise exception 'Authentication required' using errcode='42501'; end if;
 update public.notification_devices set revoked_at=now() where user_id=(select auth.uid()) and revoked_at is null;
 get diagnostics affected=row_count;
 return affected;
end $$;

create function public.ingest_notification_event(p_device_token text,p_event jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d public.notification_devices%rowtype; v_id uuid; v_time timestamptz; v_amount numeric;
 v_source text; v_kind text; v_merchant text; v_currency text; v_card text; v_key text; v_time_source text;
begin
 if p_device_token is null or p_device_token !~ '^[0-9a-f]{64}$' or p_event is null or jsonb_typeof(p_event)<>'object' then
  raise exception 'Invalid notification' using errcode='22023';
 end if;
 -- Do not allow extra keys such as raw text or OTP, even from a registered device.
 if octet_length(p_event::text)>2048 or (select count(*) from jsonb_object_keys(p_event))<>9
 or exists(select 1 from jsonb_each(p_event) where jsonb_typeof(value)<>'string')
 or not p_event ?& array['event_key','source','kind','amount','currency','merchant','card_last4','occurred_at','time_source'] then
  raise exception 'Invalid notification' using errcode='22023';
 end if;
 select * into d from public.notification_devices where token_hash=encode(extensions.digest(p_device_token,'sha256'),'hex') and revoked_at is null and expires_at>now() for update;
 if not found then raise exception 'Device unavailable' using errcode='42501'; end if;
 v_key:=p_event->>'event_key'; v_source:=p_event->>'source'; v_kind:=p_event->>'kind'; v_merchant:=btrim(p_event->>'merchant'); v_currency:=p_event->>'currency'; v_card:=p_event->>'card_last4'; v_time_source:=p_event->>'time_source';
 if v_time_source is null or v_time_source not in ('bank','notification') or (v_source='wallet' and v_time_source<>'notification') or (v_source in ('ameria','acba') and v_time_source<>'bank') or v_key is null or v_key !~ '^[0-9a-f]{64}$' or v_card is null or v_card !~ '^[0-9]{4}$'
 or v_currency is null or v_currency not in ('AMD','RUB','USD','EUR')
 or v_merchant is null or length(v_merchant) not between 2 and 120 or v_merchant ~ '[[:cntrl:]]' or length(regexp_replace(v_merchant,'[^0-9]','','g'))>=8 or v_merchant ~* '(https?://|www\.|@|(^|[^[:alpha:]])otp([^[:alpha:]]|$)|one.time|pass(word|code)|verification|(^|[^[:alpha:]])code([^[:alpha:]]|$)|парол|(^|[^[:alpha:]])код([^[:alpha:]]|$))'
 or v_source is null or v_kind is null or not ((v_source='wallet' and v_kind='purchase') or (v_source='ameria' and v_kind in ('purchase','credit')) or (v_source='acba' and v_kind in ('pre_purchase','pre_purchase_completion')))
 or coalesce(p_event->>'amount','') !~ '^[0-9]{1,16}(\.[0-9]{1,2})?$' then
  raise exception 'Invalid notification' using errcode='22023';
 end if;
 begin v_amount:=(p_event->>'amount')::numeric; v_time:=(p_event->>'occurred_at')::timestamptz;
 exception when others then raise exception 'Invalid notification' using errcode='22023'; end;
 if v_amount<=0 or v_amount>=1e18 or v_time is null or v_time<date '1900-01-01' or v_time>now()+interval '1 day' then raise exception 'Invalid notification' using errcode='22023'; end if;
 select id into v_id from public.notification_events where user_id=d.user_id and event_key=v_key;
 if v_id is not null then return jsonb_build_object('id',v_id,'duplicate',true); end if;
 if (select count(*) from public.notification_events where device_id=d.id and created_at>=now()-interval '1 day')>=1000 then raise exception 'Device rate limit' using errcode='54000'; end if;
 insert into public.notification_events(user_id,device_id,event_key,source,kind,amount,currency,merchant,card_last4,occurred_at,time_source)
 values(d.user_id,d.id,v_key,v_source,v_kind,v_amount,v_currency,v_merchant,v_card,v_time,v_time_source) returning id into v_id;
 return jsonb_build_object('id',v_id,'duplicate',false);
end $$;
create function public.dismiss_notification_event(p_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if (select auth.uid()) is null then raise exception 'Authentication required' using errcode='42501'; end if;
 update public.notification_events set dismissed_at=now() where id=p_id and user_id=(select auth.uid()) and dismissed_at is null;
 return found;
end $$;
revoke all on function public.register_notification_device() from public,anon,authenticated;
revoke all on function public.revoke_notification_device(uuid) from public,anon,authenticated;
revoke all on function public.ingest_notification_event(text,jsonb) from public,anon,authenticated;
revoke all on function public.revoke_all_notification_devices() from public,anon,authenticated;
revoke all on function public.dismiss_notification_event(uuid) from public,anon,authenticated;
grant execute on function public.register_notification_device() to authenticated;
grant execute on function public.revoke_notification_device(uuid) to authenticated;
grant execute on function public.revoke_all_notification_devices() to authenticated;
grant execute on function public.dismiss_notification_event(uuid) to authenticated;
grant execute on function public.ingest_notification_event(text,jsonb) to anon,authenticated;
