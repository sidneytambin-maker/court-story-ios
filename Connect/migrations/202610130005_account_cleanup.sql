begin;
create or replace function public.cs_delete_my_data() returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 delete from public.cs_profiles where account_id=auth.uid();
 delete from public.cs_connections where coach_account=auth.uid();
 delete from public.cs_feedback where author_id=auth.uid();
 delete from cs_private.invitations where creator=auth.uid() or accepted_by=auth.uid();
 delete from cs_private.operations where account_id=auth.uid();
 delete from public.cs_entitlements where account_id=auth.uid();
 delete from public.cs_audit where actor_id=auth.uid() or player_account=auth.uid() or coach_account=auth.uid();
 delete from cs_private.push_devices where account_id=auth.uid();
 delete from public.cs_notifications where account_id=auth.uid();
 delete from public.cs_notification_preferences where account_id=auth.uid();
 delete from public.cs_accounts where id=auth.uid();
end $$;
revoke execute on function public.cs_delete_my_data() from public,anon;
grant execute on function public.cs_delete_my_data() to authenticated;
commit;
