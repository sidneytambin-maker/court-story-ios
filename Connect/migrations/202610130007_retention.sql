begin;
create function public.cs_maintenance() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 delete from cs_private.push_deliveries where delivered_at<now()-interval '1 day' or next_attempt<now()-interval '2 days';
 delete from public.cs_notifications where created_at<now()-interval '90 days';
 delete from cs_private.invitations where expires_at<now()-interval '7 days';
 delete from public.cs_audit where occurred_at<now()-interval '365 days';
 -- Stable operation receipts and tombstone IDs remain until account deletion to prevent duplicate replay/resurrection.
 return jsonb_build_object('database_bytes',pg_database_size(current_database()),'accounts',(select count(*) from public.cs_accounts),'records',(select count(*) from public.cs_records),'pending_push',(select count(*) from cs_private.push_deliveries where delivered_at is null));
end $$;
revoke execute on function public.cs_maintenance() from public,anon,authenticated;
grant execute on function public.cs_maintenance() to service_role;
commit;
