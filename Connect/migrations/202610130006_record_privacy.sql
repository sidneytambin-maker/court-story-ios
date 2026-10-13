begin;
create function public.cs_set_record_private(p_id uuid,p_private boolean,p_expected bigint) returns bigint language plpgsql security definer set search_path='' as $$
declare r public.cs_records; revision bigint;
begin
 select * into r from public.cs_records where id=p_id and owner_id=auth.uid() for update;
 if r.id is null or r.deleted then raise exception 'Own active record required'; end if;
 if r.revision<>p_expected then raise exception 'Conflict: refresh before retrying' using errcode='40001'; end if;
 update public.cs_records set private=p_private where id=p_id returning cs_records.revision into revision;
 insert into public.cs_audit(actor_id,player_account,action,entity_id) values(auth.uid(),auth.uid(),'record_privacy_changed',p_id);
 return revision;
end $$;
revoke execute on function public.cs_set_record_private(uuid,boolean,bigint) from public,anon;
grant execute on function public.cs_set_record_private(uuid,boolean,bigint) to authenticated;
commit;
