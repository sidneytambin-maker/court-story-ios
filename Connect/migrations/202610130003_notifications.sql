begin;
create table public.cs_accounts (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check(length(trim(display_name)) between 1 and 120)
);
alter table public.cs_accounts enable row level security;
revoke all on public.cs_accounts from anon,authenticated;
grant select on public.cs_accounts to authenticated;
create policy own_account on public.cs_accounts for select to authenticated using(id=auth.uid());
alter table public.cs_connections add column player_name text not null default 'Player';
alter table public.cs_connections add column coach_name text not null default 'Coach';
create or replace function public.cs_register_profile(p_id uuid,p_name text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.cs_profiles values(p_id,auth.uid(),p_name)
 on conflict(id) do update set display_name=excluded.display_name where cs_profiles.account_id=auth.uid();
 if not found then raise exception 'Profile belongs to another account'; end if;
 insert into public.cs_accounts values(auth.uid(),p_name) on conflict(id) do update set display_name=excluded.display_name;
end $$;
create table public.cs_notification_preferences (
 account_id uuid primary key references auth.users(id) on delete cascade,
 push_enabled boolean not null default false,
 connection_requests boolean not null default true,
 sharing_confirmations boolean not null default true,
 coach_feedback boolean not null default true,
 updated_at timestamptz not null default now()
);
create table public.cs_notifications (
 id uuid primary key default gen_random_uuid(), account_id uuid not null references auth.users(id) on delete cascade,
 connection_id uuid references public.cs_connections(id) on delete cascade,
 kind text not null check(kind in ('connection_request','sharing_started','sharing_stopped','coach_feedback')),
 message text not null, created_at timestamptz not null default now(), read_at timestamptz
);
create table cs_private.push_devices (
 account_id uuid not null references auth.users(id) on delete cascade, installation_id uuid not null,
 platform text not null check(platform in ('apns','fcm')), token text not null check(length(token) between 20 and 4096),
 updated_at timestamptz not null default now(), primary key(account_id,installation_id), unique(platform,token)
);
create table cs_private.push_deliveries (
 notification_id uuid not null references public.cs_notifications(id) on delete cascade,
 installation_id uuid not null, account_id uuid not null references auth.users(id) on delete cascade,
 attempts integer not null default 0, next_attempt timestamptz not null default now(), delivered_at timestamptz,
 primary key(notification_id,installation_id),
 foreign key(account_id,installation_id) references cs_private.push_devices(account_id,installation_id) on delete cascade
);
alter table public.cs_notification_preferences enable row level security;
alter table public.cs_notifications enable row level security;
revoke all on public.cs_notification_preferences,public.cs_notifications from anon,authenticated;
grant select on public.cs_notification_preferences,public.cs_notifications to authenticated;
create policy own_notification_settings on public.cs_notification_preferences for select to authenticated using(account_id=auth.uid());
create policy own_notifications on public.cs_notifications for select to authenticated using(account_id=auth.uid());

create function public.cs_set_notifications(p_push boolean,p_requests boolean,p_sharing boolean,p_feedback boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.cs_notification_preferences values(auth.uid(),p_push,p_requests,p_sharing,p_feedback,now())
 on conflict(account_id) do update set push_enabled=p_push,connection_requests=p_requests,sharing_confirmations=p_sharing,coach_feedback=p_feedback,updated_at=now();
end $$;
create function public.cs_register_device(p_installation uuid,p_platform text,p_token text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 -- Transfer a device on explicit sign-in so an old account's messages cannot arrive on a new account.
 delete from cs_private.push_devices where platform=p_platform and token=p_token and account_id<>auth.uid();
 insert into cs_private.push_devices values(auth.uid(),p_installation,p_platform,p_token,now())
 on conflict(account_id,installation_id) do update set platform=p_platform,token=p_token,updated_at=now();
end $$;
create function public.cs_unregister_device(p_installation uuid) returns void language sql security definer set search_path='' as $$
 delete from cs_private.push_devices where account_id=auth.uid() and installation_id=p_installation
$$;
create function public.cs_read_notification(p_id uuid) returns void language sql security definer set search_path='' as $$
 update public.cs_notifications set read_at=now() where id=p_id and account_id=auth.uid()
$$;

create function cs_private.notify_connection() returns trigger language plpgsql security definer set search_path='' as $$
begin
 new.player_name:=coalesce((select display_name from public.cs_profiles where id=new.player_id),'Player');
 new.coach_name:=coalesce((select display_name from public.cs_accounts where id=new.coach_account),'Coach');
 return new;
end $$;
create trigger cs_connection_names before insert or update on public.cs_connections for each row execute function cs_private.notify_connection();
create function cs_private.connection_notification() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' or (new.state='pending' and old.state is distinct from new.state) then
  insert into public.cs_notifications(account_id,connection_id,kind,message) values(new.player_account,new.id,'connection_request',new.coach_name||' accepted your connection invitation. Review and approve what you share.');
 elsif new.state='active' and old.state is distinct from new.state and cardinality(new.categories)>0 then
  insert into public.cs_notifications(account_id,connection_id,kind,message) values(new.player_account,new.id,'sharing_started','Your permitted sporting data is now being shared with '||new.coach_name||'.');
  insert into public.cs_notifications(account_id,connection_id,kind,message) values(new.coach_account,new.id,'sharing_started',new.player_name||' approved sporting data sharing with you.');
 elsif new.state in ('paused','revoked') and old.state is distinct from new.state then
  insert into public.cs_notifications(account_id,connection_id,kind,message) values(new.player_account,new.id,'sharing_stopped','Sharing with '||new.coach_name||' is '||new.state||'.');
 end if;
 return new;
end $$;
create trigger cs_connection_notification after insert or update on public.cs_connections for each row execute function cs_private.connection_notification();
create function cs_private.queue_push() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into cs_private.push_deliveries(notification_id,installation_id,account_id)
 select new.id,d.installation_id,d.account_id from cs_private.push_devices d join public.cs_notification_preferences p on p.account_id=d.account_id
 where d.account_id=new.account_id and p.push_enabled and
 case new.kind when 'connection_request' then p.connection_requests when 'coach_feedback' then p.coach_feedback else p.sharing_confirmations end;
 return new;
end $$;
create trigger cs_queue_push after insert on public.cs_notifications for each row execute function cs_private.queue_push();
create function public.cs_claim_push(p_limit integer default 50) returns table(notification_id uuid,installation_id uuid,platform text,token text,message text,connection_id uuid) language plpgsql security definer set search_path='' as $$
begin
 return query with claim as (
  select d.notification_id,d.installation_id from cs_private.push_deliveries d join public.cs_notifications n on n.id=d.notification_id
  join public.cs_notification_preferences p on p.account_id=d.account_id
  where d.delivered_at is null and d.attempts<8 and d.next_attempt<=now() and n.created_at>now()-interval '24 hours'
  and p.push_enabled and case n.kind when 'connection_request' then p.connection_requests when 'coach_feedback' then p.coach_feedback else p.sharing_confirmations end
  order by d.next_attempt for update of d skip locked limit greatest(1,least(p_limit,100))
 ), leased as (
  update cs_private.push_deliveries d set attempts=attempts+1,next_attempt=now()+interval '5 minutes'
  from claim c where d.notification_id=c.notification_id and d.installation_id=c.installation_id returning d.*
 ) select l.notification_id,l.installation_id,v.platform,v.token,n.message,n.connection_id from leased l
 join cs_private.push_devices v on v.account_id=l.account_id and v.installation_id=l.installation_id
 join public.cs_notifications n on n.id=l.notification_id;
end $$;
create function public.cs_finish_push(p_notification uuid,p_installation uuid,p_delivered boolean,p_invalid boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 update cs_private.push_deliveries set delivered_at=case when p_delivered then now() else null end,
 next_attempt=now()+interval '1 minute'*power(2,attempts) where notification_id=p_notification and installation_id=p_installation;
 if p_invalid then delete from cs_private.push_devices where installation_id=p_installation and account_id=(select account_id from public.cs_notifications where id=p_notification); end if;
end $$;
revoke execute on all functions in schema cs_private from public,anon,authenticated;
grant execute on function cs_private.can_read(public.cs_records) to authenticated;
revoke execute on function public.cs_set_notifications(boolean,boolean,boolean,boolean),public.cs_register_device(uuid,text,text),public.cs_unregister_device(uuid),public.cs_read_notification(uuid),public.cs_claim_push(integer),public.cs_finish_push(uuid,uuid,boolean,boolean) from public,anon,authenticated;
grant execute on function public.cs_set_notifications(boolean,boolean,boolean,boolean),public.cs_register_device(uuid,text,text),public.cs_unregister_device(uuid),public.cs_read_notification(uuid) to authenticated;
grant execute on function public.cs_claim_push(integer),public.cs_finish_push(uuid,uuid,boolean,boolean) to service_role;
commit;
