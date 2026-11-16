-- Run manually on the intended Supabase project only after provisioning the
-- gmail_project_url and gmail_service_role secrets in Supabase Vault.
-- This does not create secrets or contact Gmail until the scheduled run.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
do $$
begin
 if (select count(*) from vault.decrypted_secrets where name='gmail_project_url')<>1
    or (select count(*) from vault.decrypted_secrets where name='gmail_service_role')<>1 then
  raise exception 'Expected one gmail_project_url and one gmail_service_role in Vault';
 end if;
 if (select decrypted_secret from vault.decrypted_secrets where name='gmail_service_role') !~ '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' then
  raise exception 'Expected legacy JWT service role key';
 end if;
 if (select decrypted_secret from vault.decrypted_secrets where name='gmail_project_url') !~ '^https://[a-z0-9]+\.supabase\.co$' then
  raise exception 'Invalid Supabase project URL';
 end if;
 perform cron.schedule('cash-radar-gmail-collector','*/15 * * * *',
 $job$select net.http_post(
   url:=(select decrypted_secret from vault.decrypted_secrets where name='gmail_project_url') || '/functions/v1/gmail-collector',
   headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name='gmail_service_role')),
   body:='{}'::jsonb,
   timeout_milliseconds:=120000
 );$job$);
end $$;
