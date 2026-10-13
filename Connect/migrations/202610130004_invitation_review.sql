begin;
create function public.cs_preview_invitation(p_code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare i cs_private.invitations; email text;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select lower(u.email) into email from auth.users u where id=auth.uid() and email_confirmed_at is not null;
 select * into i from cs_private.invitations where token_hash=sha256(convert_to(p_code,'UTF8'));
 if p_code !~ '^[a-f0-9]{64}$' or i.id is null or i.expires_at<=now() or i.accepted_at is not null or i.creator=auth.uid() or email is null or (i.recipient_email is not null and i.recipient_email<>email) then raise exception 'Invalid or unavailable invitation'; end if;
 return jsonb_build_object('role',i.role,'sport',i.sport,'expires_at',i.expires_at,'name',coalesce((select display_name from public.cs_accounts where id=i.creator),'Court Story member'));
end $$;
create function public.cs_decline_invitation(p_code text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.cs_preview_invitation(p_code);
 update cs_private.invitations set accepted_by=auth.uid(),accepted_at=now() where token_hash=sha256(convert_to(p_code,'UTF8')) and accepted_at is null;
 if not found then raise exception 'Invitation is no longer available'; end if;
end $$;
create function public.cs_leave_connection(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.cs_connections set state='revoked',updated_at=now() where id=p_id and coach_account=auth.uid() and state<>'revoked';
 if not found then raise exception 'Connection is unavailable'; end if;
end $$;
create function cs_private.feedback_notification() returns trigger language plpgsql security definer set search_path='' as $$
declare c public.cs_connections;
begin
 select * into c from public.cs_connections where id=new.connection_id;
 insert into public.cs_notifications(account_id,connection_id,kind,message) values(c.player_account,c.id,'coach_feedback',c.coach_name||' sent coach feedback.');
 return new;
end $$;
create trigger cs_feedback_notification after insert on public.cs_feedback for each row execute function cs_private.feedback_notification();
revoke execute on function public.cs_preview_invitation(text),public.cs_decline_invitation(text),public.cs_leave_connection(uuid),cs_private.feedback_notification() from public,anon,authenticated;
grant execute on function public.cs_preview_invitation(text),public.cs_decline_invitation(text),public.cs_leave_connection(uuid) to authenticated;
commit;
