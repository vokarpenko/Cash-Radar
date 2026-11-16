-- One row per Gmail attachment. Original messages and OAuth credentials are not stored here.
create table public.gmail_import_jobs (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 account_id uuid not null,
 message_id text not null check (length(message_id) between 1 and 256 and message_id ~ '^[A-Za-z0-9_-]+$'),
 attachment_id text not null check (length(attachment_id) between 1 and 256 and attachment_id ~ '^[A-Za-z0-9_-]+$'),
 status text not null check (status in ('working','complete','failed')),
 error_code text check (error_code is null or error_code ~ '^[a-z_]{1,64}$'),
 batch_id uuid,
 lease_token uuid,
 lease_until timestamptz,
 attempts integer not null default 0 check (attempts between 0 and 1000000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(user_id,message_id,attachment_id),
 foreign key (user_id, account_id) references public.accounts(user_id,id),
 foreign key (user_id, batch_id) references public.import_batches(user_id,id)
);
alter table public.gmail_import_jobs enable row level security;
revoke all on public.gmail_import_jobs from public, anon, authenticated;
grant select (id,user_id,account_id,status,error_code,batch_id,attempts,created_at,updated_at) on public.gmail_import_jobs to authenticated;
grant all on public.gmail_import_jobs to service_role;
create policy gmail_jobs_owner on public.gmail_import_jobs for select to authenticated using (user_id=(select auth.uid()));

-- Claims expire so a terminated worker can resume. Completed work is never re-run.
create function public.gmail_claim_attachment(p_user uuid,p_account uuid,p_message text,p_attachment text,p_lease uuid)
returns text language plpgsql security definer set search_path='' as $$
declare j public.gmail_import_jobs%rowtype;
begin
 if p_user is null or p_account is null or p_lease is null or coalesce(length(p_message),0) not between 1 and 256 or p_message !~ '^[A-Za-z0-9_-]+$' or coalesce(length(p_attachment),0) not between 1 and 256 or p_attachment !~ '^[A-Za-z0-9_-]+$' then
  raise exception 'Invalid collector claim' using errcode='22023';
 end if;
 if not exists(select 1 from public.accounts a where a.id=p_account and a.user_id=p_user and a.is_active) then
  raise exception 'Account unavailable' using errcode='22023';
 end if;
 insert into public.gmail_import_jobs(user_id,account_id,message_id,attachment_id,status,lease_token,lease_until,attempts)
 values(p_user,p_account,p_message,p_attachment,'working',p_lease,now()+interval '3 minutes',1)
 on conflict(user_id,message_id,attachment_id) do nothing;
 select * into j from public.gmail_import_jobs where user_id=p_user and message_id=p_message and attachment_id=p_attachment for update;
 if j.account_id<>p_account then return 'wrong_account'; end if;
 if j.status='complete' then return 'complete'; end if;
 if j.lease_token=p_lease then return 'claimed'; end if;
 if j.status='working' and j.lease_until>now() then return 'busy'; end if;
 if j.status='failed' and j.updated_at>now()-interval '1 minute' then return 'busy'; end if;
 update public.gmail_import_jobs set status='working',error_code=null,lease_token=p_lease,lease_until=now()+interval '3 minutes',attempts=attempts+1,updated_at=now() where id=j.id;
 return 'claimed';
end;
$$;
create function public.gmail_finish_attachment(p_user uuid,p_message text,p_attachment text,p_lease uuid,p_batch uuid,p_error text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if (p_batch is null)=(p_error is null) or (p_error is not null and p_error !~ '^[a-z_]{1,64}$') then
  raise exception 'Invalid collector result' using errcode='22023';
 end if;
 update public.gmail_import_jobs set status=case when p_error is null then 'complete' else 'failed' end,
  batch_id=p_batch,error_code=p_error,lease_token=null,lease_until=null,updated_at=now()
 where user_id=p_user and message_id=p_message and attachment_id=p_attachment and status='working' and lease_token=p_lease and lease_until>now();
 return found;
end;
$$;
revoke all on function public.gmail_claim_attachment(uuid,uuid,text,text,uuid) from public,anon,authenticated;
revoke all on function public.gmail_finish_attachment(uuid,text,text,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.gmail_claim_attachment(uuid,uuid,text,text,uuid) to service_role;
grant execute on function public.gmail_finish_attachment(uuid,text,text,uuid,uuid,text) to service_role;

-- The cursor rotates through a label even if some messages repeatedly fail.
create table public.gmail_poll_cursors (
 user_id uuid not null references auth.users(id) on delete cascade,
 label_id text not null check (label_id ~ '^Label_[A-Za-z0-9_-]{1,250}$'),
 page_token text check (page_token is null or length(page_token) between 1 and 2048),
 updated_at timestamptz not null default now(),
 primary key (user_id,label_id)
);
alter table public.gmail_poll_cursors enable row level security;
revoke all on public.gmail_poll_cursors from public,anon,authenticated;
grant all on public.gmail_poll_cursors to service_role;

-- Operational status contains only counters and a safe error code, never email contents.
create table public.gmail_collector_runs (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 scanned integer not null default 0 check(scanned between 0 and 100),
 prepared integer not null default 0 check(prepared between 0 and 1000),
 failed integer not null default 0 check(failed between 0 and 1000),
 error_code text check(error_code is null or error_code ~ '^[a-z_]{1,64}$'),
 created_at timestamptz not null default now()
);
create index gmail_collector_runs_owner_created on public.gmail_collector_runs(user_id,created_at desc);
alter table public.gmail_collector_runs enable row level security;
revoke all on public.gmail_collector_runs from public,anon,authenticated;
grant select on public.gmail_collector_runs to authenticated;
grant all on public.gmail_collector_runs to service_role;
create policy gmail_runs_owner on public.gmail_collector_runs for select to authenticated using (user_id=(select auth.uid()));
