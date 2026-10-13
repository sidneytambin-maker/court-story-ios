-- Hosted Supabase only. Provision cs_project_url, cs_gateway_anon_key and
-- cs_dispatch_secret in Vault before applying. Never put their values in Git.
begin;
create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function cs_private.dispatch_due_notifications()
returns bigint language plpgsql security definer set search_path='' as $$
declare project_url text; gateway_key text; dispatch_key text; request_id bigint;
begin
  -- Idle projects do not spend function invocations polling an empty queue.
  if not exists(select 1 from cs_private.push_deliveries d
    join public.cs_notification_preferences p on p.account_id=d.account_id
    where d.delivered_at is null and d.next_attempt<=now()
      and d.attempts<8 and p.push_enabled) then return null; end if;
  select decrypted_secret into project_url from vault.decrypted_secrets where name='cs_project_url';
  select decrypted_secret into gateway_key from vault.decrypted_secrets where name='cs_gateway_anon_key';
  select decrypted_secret into dispatch_key from vault.decrypted_secrets where name='cs_dispatch_secret';
  if project_url is null or gateway_key is null or dispatch_key is null then
    raise exception 'Connect scheduler configuration incomplete';
  end if;
  select net.http_post(url:=project_url||'/functions/v1/dispatch-notifications',
    headers:=jsonb_build_object('Content-Type','application/json',
      'Authorization','Bearer '||gateway_key,'X-Connect-Dispatch-Secret',dispatch_key),
    body:='{}'::jsonb,timeout_milliseconds:=30000) into request_id;
  return request_id;
end $$;
revoke execute on function cs_private.dispatch_due_notifications() from public,anon,authenticated;
select cron.schedule('court-story-connect-push','* * * * *',
  'select cs_private.dispatch_due_notifications()');
select cron.schedule('court-story-connect-retention','17 3 * * *',
  'select public.cs_maintenance()');
commit;
