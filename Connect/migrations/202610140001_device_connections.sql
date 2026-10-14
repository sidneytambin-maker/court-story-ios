begin;
-- Device sessions may accept unbound invitations without email registration.
create or replace function public.cs_accept_invitation(p_code text,p_player uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare i cs_private.invitations; player uuid; owner uuid; coach uuid; connection uuid; email text;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_code !~ '^[a-f0-9]{64}$' then raise exception 'Invalid or unavailable invitation'; end if;
 select * into i from cs_private.invitations where token_hash=sha256(convert_to(p_code,'UTF8')) for update;
 select lower(u.email) into email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
 if i.id is null or i.expires_at<=now() or i.accepted_at is not null or i.creator=auth.uid() or (i.recipient_email is not null and (email is null or i.recipient_email<>email)) then raise exception 'Invalid or unavailable invitation'; end if;
 if i.role='player' then player:=i.player_id; owner:=i.creator; coach:=auth.uid();
 else player:=p_player; owner:=auth.uid(); coach:=i.creator;
  if not exists(select 1 from public.cs_profiles where id=player and account_id=owner) then raise exception 'Choose your own player profile'; end if;
 end if;
 insert into public.cs_connections(player_id,player_account,coach_account,sport) values(player,owner,coach,i.sport)
 on conflict(player_id,coach_account,sport) do update set state='pending',categories='{}',approved_at=null,updated_at=now()
 where cs_connections.state='revoked' returning id into connection;
 if connection is null then raise exception 'Connection already exists'; end if;
 update cs_private.invitations set accepted_at=now(),accepted_by=auth.uid() where id=i.id;
 insert into public.cs_audit(actor_id,player_account,coach_account,action,entity_id) values(auth.uid(),owner,coach,'invitation_accepted',connection);
 return connection;
end $$;

create or replace function public.cs_preview_invitation(p_code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare i cs_private.invitations; email text;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select lower(u.email) into email from auth.users u where id=auth.uid() and email_confirmed_at is not null;
 select * into i from cs_private.invitations where token_hash=sha256(convert_to(p_code,'UTF8'));
 if p_code !~ '^[a-f0-9]{64}$' or i.id is null or i.expires_at<=now() or i.accepted_at is not null or i.creator=auth.uid() or (i.recipient_email is not null and (email is null or i.recipient_email<>email)) then raise exception 'Invalid or unavailable invitation'; end if;
 return jsonb_build_object('role',i.role,'sport',i.sport,'expires_at',i.expires_at,'name',coalesce((select display_name from public.cs_accounts where id=i.creator),'Court Story member'));
end $$;

commit;
