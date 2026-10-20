begin;
-- A private receipt lets the same device safely retry after losing a response.
-- Legacy invitation RPCs keep their original one-use contract.
create table cs_private.invitation_responses (
 invitation_id uuid primary key references cs_private.invitations(id) on delete cascade,
 account_id uuid not null references auth.users(id) on delete cascade,
 response text not null check(response in ('accept','decline')),
 connection_id uuid,
 player_id uuid,
 created_at timestamptz not null default now()
);
alter table cs_private.invitation_responses enable row level security;
revoke all on cs_private.invitation_responses from public,anon,authenticated;
create function public.cs_review_invitation(p_code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare i cs_private.invitations; r cs_private.invitation_responses;
begin
 if auth.uid() is null or p_code is null or p_code !~ '^[a-f0-9]{64}$' then raise exception 'Invalid or unavailable invitation'; end if;
 select * into i from cs_private.invitations where token_hash=sha256(convert_to(p_code,'UTF8'));
 select * into r from cs_private.invitation_responses where invitation_id=i.id and account_id=auth.uid();
 if r.invitation_id is null then return public.cs_preview_invitation(p_code); end if;
 return jsonb_build_object('role',i.role,'sport',i.sport,'expires_at',i.expires_at,'name',coalesce((select display_name from public.cs_accounts where id=i.creator),'Court Story member'),'response',r.response,'connection_id',r.connection_id);
end $$;
create function public.cs_respond_invitation(p_code text,p_response text,p_player uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare i cs_private.invitations; r cs_private.invitation_responses; connection uuid; selected_player uuid;
begin
 if auth.uid() is null or p_code is null or p_code !~ '^[a-f0-9]{64}$' or p_response is null or p_response not in ('accept','decline') then raise exception 'Invalid or unavailable invitation'; end if;
 select * into i from cs_private.invitations where token_hash=sha256(convert_to(p_code,'UTF8')) for update;
 if i.id is null then raise exception 'Invalid or unavailable invitation'; end if;
 selected_player:=case when p_response='accept' and i.role='coach' then p_player else null end;
 select * into r from cs_private.invitation_responses where invitation_id=i.id;
 if r.invitation_id is not null then
  if r.account_id<>auth.uid() or r.response<>p_response or r.player_id is distinct from selected_player then raise exception 'This invitation has already been answered'; end if;
  return jsonb_build_object('response',r.response,'connection_id',r.connection_id);
 end if;
 if p_response='accept' then connection:=public.cs_accept_invitation(p_code,p_player);
 else perform public.cs_decline_invitation(p_code); end if;
 insert into cs_private.invitation_responses(invitation_id,account_id,response,connection_id,player_id) values(i.id,auth.uid(),p_response,connection,selected_player);
 return jsonb_build_object('response',p_response,'connection_id',connection);
end $$;
revoke execute on function public.cs_review_invitation(text),public.cs_respond_invitation(text,text,uuid) from public,anon,authenticated;
grant execute on function public.cs_review_invitation(text),public.cs_respond_invitation(text,text,uuid) to authenticated;
commit;
