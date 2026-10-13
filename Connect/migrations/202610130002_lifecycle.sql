begin;
create function public.cs_replace_participants(p_record uuid,p_expected bigint,p_people jsonb) returns bigint language plpgsql security definer set search_path='' as $$
declare r public.cs_records; person jsonb; revision bigint;
begin
 select * into r from public.cs_records where id=p_record for update;
 if r.id is null or auth.uid() is null or r.owner_id<>auth.uid() or r.deleted then raise exception 'Own active record required'; end if;
 if r.revision<>p_expected then raise exception 'Conflict: refresh before retrying' using errcode='40001'; end if;
 if jsonb_typeof(p_people)<>'array' or jsonb_array_length(p_people)>64 then raise exception 'Invalid participants'; end if;
 delete from public.cs_participants where record_id=p_record;
 for person in select value from jsonb_array_elements(p_people) loop
  if person-array['id','display_name','team']<>'{}'::jsonb then raise exception 'Invalid participant fields'; end if;
  insert into public.cs_participants values(p_record,(person->>'id')::uuid,person->>'display_name',(person->>'team')::integer);
 end loop;
 update public.cs_records set updated_at=now() where id=p_record returning cs_records.revision into revision;
 return revision;
end $$;
-- SECURITY INVOKER is intentional: grants and RLS must apply to every row.
create function public.cs_visible_manifest(p_after uuid default '00000000-0000-0000-0000-000000000000',p_limit integer default 200)
returns table(id uuid,revision bigint) language sql stable security invoker set search_path='' as $$
 select r.id,r.revision from public.cs_records r where r.id>p_after and not r.deleted order by r.id limit greatest(1,least(p_limit,200))
$$;
create function public.cs_delete_my_data() returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 delete from public.cs_profiles where account_id=auth.uid();
 delete from public.cs_connections where coach_account=auth.uid();
 delete from public.cs_feedback where author_id=auth.uid();
 delete from cs_private.invitations where creator=auth.uid() or accepted_by=auth.uid();
 delete from cs_private.operations where account_id=auth.uid();
 delete from public.cs_entitlements where account_id=auth.uid();
 delete from public.cs_audit where actor_id=auth.uid() or player_account=auth.uid() or coach_account=auth.uid();
end $$;
revoke execute on function public.cs_replace_participants(uuid,bigint,jsonb),public.cs_visible_manifest(uuid,integer),public.cs_delete_my_data() from public,anon;
grant execute on function public.cs_replace_participants(uuid,bigint,jsonb),public.cs_visible_manifest(uuid,integer),public.cs_delete_my_data() to authenticated;
commit;
