-- Court Story Connect protocol 1. No existing local library migration.
begin;
create schema if not exists cs_private;
revoke all on schema cs_private from public;

create table public.cs_profiles (
  id uuid primary key, account_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check(length(display_name) between 1 and 120),
  unique(id, account_id)
);
create table public.cs_connections (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null, player_account uuid not null references auth.users(id) on delete cascade,
  coach_account uuid not null references auth.users(id) on delete cascade,
  sport text not null check(length(sport) between 1 and 120),
  state text not null default 'pending' check(state in ('pending','active','paused','revoked')),
  categories text[] not null default '{}',
  history text not null default 'future' check(history in ('future','all','period')),
  history_start timestamptz, history_end timestamptz,
  future_sharing boolean not null default true,
  capability text not null default 'view' check(capability in ('view','feedback','contribute')),
  approved_at timestamptz, updated_at timestamptz not null default now(),
  foreign key(player_id,player_account) references public.cs_profiles(id,account_id) on delete cascade,
  unique(player_id,coach_account,sport), check(player_account <> coach_account),
  check(categories <@ array['match','training','tournament','note','reflection','goal']),
  check(history <> 'period' or (history_start is not null and history_end is not null and history_end >= history_start))
);
create table cs_private.invitations (
  id uuid primary key default gen_random_uuid(), creator uuid not null references auth.users(id) on delete cascade,
  role text not null check(role in ('player','coach')), player_id uuid references public.cs_profiles(id) on delete cascade,
  sport text not null check(length(sport) between 1 and 120), token_hash bytea unique not null,
  recipient_email text, expires_at timestamptz not null, accepted_by uuid references auth.users(id) on delete cascade,
  accepted_at timestamptz, created_at timestamptz not null default now()
);
create sequence cs_private.change_sequence;
create table public.cs_records (
  id uuid primary key, player_id uuid not null, owner_id uuid not null references auth.users(id) on delete cascade,
  sport text not null check(length(sport) between 1 and 120),
  category text not null check(category in ('match','training','tournament','note','reflection','goal')),
  occurred_at timestamptz not null, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), revision bigint not null default 1,
  change_id bigint not null, private boolean not null default false, deleted boolean not null default false,
  body jsonb not null, foreign key(player_id,owner_id) references public.cs_profiles(id,account_id) on delete cascade,
  check(jsonb_typeof(body)='object' and octet_length(body::text)<=16384),
  check(body - array['title','result','score','duration_minutes','focus','text','status','matchType','matchFormat','yourSetsWon','opponentSetsWon','aces','doubleFaults','winners','unforcedErrors','hadTiebreak','tiebreakScore','tournamentID','trainingSessionID','finalResult','matchesPlayed','format','stageReached','finishingPosition','endDate'] = '{}'::jsonb)
);
create table public.cs_participants (
  record_id uuid not null references public.cs_records(id) on delete cascade,
  id uuid not null, display_name text not null check(length(display_name) between 1 and 120),
  team integer not null check(team between 0 and 32), primary key(record_id,id)
);
create table public.cs_feedback (
  id uuid primary key, connection_id uuid not null references public.cs_connections(id) on delete cascade,
  record_id uuid not null references public.cs_records(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check(kind in ('feedback','goal','contribution')),
  text text not null check(length(text) between 1 and 4000),
  state text not null default 'pending' check(state in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);
create table public.cs_audit (
  id bigint generated always as identity primary key, actor_id uuid references auth.users(id) on delete set null,
  player_account uuid references auth.users(id) on delete cascade, coach_account uuid references auth.users(id) on delete cascade,
  action text not null, entity_id uuid, occurred_at timestamptz not null default now()
);
create table public.cs_entitlements (
  account_id uuid not null references auth.users(id) on delete cascade,
  entitlement text not null, expires_at timestamptz, primary key(account_id,entitlement)
);
create table cs_private.operations (
  account_id uuid not null references auth.users(id) on delete cascade, operation_id uuid not null,
  request_hash bytea not null, response jsonb not null, created_at timestamptz not null default now(),
  primary key(account_id,operation_id)
);
create index cs_records_feed on public.cs_records(change_id);
create index cs_records_owner on public.cs_records(owner_id,player_id,sport);
create index cs_connections_coach on public.cs_connections(coach_account,state);
create index cs_feedback_record on public.cs_feedback(record_id);

create function cs_private.can_read(r public.cs_records) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (r.owner_id=auth.uid() or (not r.private and not r.deleted and exists(
  select 1 from public.cs_connections c where c.player_id=r.player_id and c.player_account=r.owner_id
   and c.coach_account=auth.uid() and c.state='active' and c.sport=r.sport and r.category=any(c.categories)
   and (c.history='all' or (c.history='future' and r.occurred_at>=c.approved_at and r.created_at>=c.approved_at)
        or (c.history='period' and r.occurred_at>=c.history_start and r.occurred_at<=c.history_end))
   and (c.future_sharing or r.occurred_at<=c.approved_at))))
$$;
create function cs_private.record_clock() returns trigger language plpgsql security definer set search_path='' as $$
begin
 -- Serialize feed allocation until commit, so a committed cursor cannot skip an earlier uncommitted change.
 perform pg_advisory_xact_lock(1734219001);
 new.change_id:=nextval('cs_private.change_sequence'); new.updated_at:=clock_timestamp();
 if TG_OP='UPDATE' then new.revision:=old.revision+1; new.created_at:=old.created_at; end if;
 return new;
end $$;
create trigger cs_record_clock before insert or update on public.cs_records for each row execute function cs_private.record_clock();

alter table public.cs_profiles enable row level security;
alter table public.cs_connections enable row level security;
alter table public.cs_records enable row level security;
alter table public.cs_participants enable row level security;
alter table public.cs_feedback enable row level security;
alter table public.cs_audit enable row level security;
alter table public.cs_entitlements enable row level security;
create policy own_profile on public.cs_profiles for select to authenticated using(account_id=auth.uid());
create policy connection_parties on public.cs_connections for select to authenticated using(auth.uid() in (player_account,coach_account));
create policy permitted_record on public.cs_records for select to authenticated using(cs_private.can_read(cs_records));
create policy permitted_participant on public.cs_participants for select to authenticated using(exists(select 1 from public.cs_records r where r.id=record_id));
create policy permitted_feedback on public.cs_feedback for select to authenticated using(exists(
 select 1 from public.cs_connections c join public.cs_records r on r.id=record_id where c.id=connection_id
 and (c.player_account=auth.uid() or (c.coach_account=auth.uid() and c.state='active' and cs_private.can_read(r)))));
create policy audit_parties on public.cs_audit for select to authenticated using(auth.uid() in (player_account,coach_account));
create policy own_entitlement on public.cs_entitlements for select to authenticated using(account_id=auth.uid());
revoke all on public.cs_profiles,public.cs_connections,public.cs_records,public.cs_participants,public.cs_feedback,public.cs_audit,public.cs_entitlements from anon,authenticated;
grant select on public.cs_profiles,public.cs_connections,public.cs_records,public.cs_participants,public.cs_feedback,public.cs_audit,public.cs_entitlements to authenticated;
grant usage on schema cs_private to authenticated;
grant execute on function cs_private.can_read(public.cs_records) to authenticated;

create function public.cs_register_profile(p_id uuid,p_name text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.cs_profiles values(p_id,auth.uid(),p_name)
 on conflict(id) do update set display_name=excluded.display_name where cs_profiles.account_id=auth.uid();
 if not found then raise exception 'Profile belongs to another account'; end if;
end $$;

create function public.cs_create_invitation(p_role text,p_player uuid,p_sport text,p_recipient text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare token text:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''); invitation uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_role not in ('player','coach') or (p_role='player' and not exists(select 1 from public.cs_profiles where id=p_player and account_id=auth.uid())) then raise exception 'Invalid player'; end if;
 if (select count(*) from cs_private.invitations where creator=auth.uid() and created_at>now()-interval '1 hour')>=20 then raise exception 'Invitation limit reached'; end if;
 insert into cs_private.invitations(creator,role,player_id,sport,token_hash,recipient_email,expires_at)
 values(auth.uid(),p_role,case when p_role='player' then p_player else null end,p_sport,sha256(convert_to(token,'UTF8')),nullif(lower(trim(p_recipient)),''),now()+interval '48 hours') returning id into invitation;
 return jsonb_build_object('id',invitation,'code',token,'expires_at',now()+interval '48 hours');
end $$;
create function public.cs_accept_invitation(p_code text,p_player uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare i cs_private.invitations; player uuid; owner uuid; coach uuid; connection uuid; email text;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_code !~ '^[a-f0-9]{64}$' then raise exception 'Invalid or unavailable invitation'; end if;
 select * into i from cs_private.invitations where token_hash=sha256(convert_to(p_code,'UTF8')) for update;
 select lower(u.email) into email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
 if i.id is null or i.expires_at<=now() or i.accepted_at is not null or i.creator=auth.uid() or email is null or (i.recipient_email is not null and i.recipient_email<>email) then raise exception 'Invalid or unavailable invitation'; end if;
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
create function public.cs_set_permission(p_id uuid,p_state text,p_categories text[],p_history text default 'future',p_start timestamptz default null,p_end timestamptz default null,p_future boolean default true,p_capability text default 'view')
returns void language plpgsql security definer set search_path='' as $$
declare c public.cs_connections;
begin
 select * into c from public.cs_connections where id=p_id and player_account=auth.uid() for update;
 if c.id is null then raise exception 'Only the player can approve sharing'; end if;
 if c.state='revoked' then raise exception 'A new invitation is required'; end if;
 if p_state not in ('active','paused','revoked') then raise exception 'Invalid state'; end if;
 update public.cs_connections set state=p_state,categories=p_categories,history=p_history,history_start=p_start,history_end=p_end,
 future_sharing=p_future,capability=p_capability,approved_at=coalesce(approved_at,clock_timestamp()),updated_at=clock_timestamp() where id=p_id;
 insert into public.cs_audit(actor_id,player_account,coach_account,action,entity_id) values(auth.uid(),c.player_account,c.coach_account,'permission_'||p_state,p_id);
end $$;

create function public.cs_put_record(p_operation uuid,p_id uuid,p_player uuid,p_sport text,p_category text,p_occurred timestamptz,p_body jsonb,p_expected bigint default 0,p_private boolean default false,p_deleted boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare previous cs_private.operations; r public.cs_records; response jsonb; request jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.cs_profiles where id=p_player and account_id=auth.uid()) then raise exception 'Own player profile required'; end if;
 -- Reject unknown/nested fields: never accept a serialized local library or Health object.
 if jsonb_typeof(p_body)<>'object' or exists(select 1 from jsonb_each(p_body) e where jsonb_typeof(e.value) not in ('string','number','null')) then raise exception 'Structured sporting fields only'; end if;
 request:=jsonb_build_array(p_id,p_player,p_sport,p_category,p_occurred,p_body,p_expected,p_private,p_deleted);
 perform pg_advisory_xact_lock(1734219001);
 select * into previous from cs_private.operations where account_id=auth.uid() and operation_id=p_operation;
 if found then
  if previous.request_hash<>sha256(convert_to(request::text,'UTF8')) then raise exception 'Operation ID reused with different content'; end if;
  return previous.response;
 end if;
 select * into r from public.cs_records where id=p_id for update;
 if found then
  if r.owner_id<>auth.uid() or r.player_id<>p_player or r.sport<>p_sport or r.category<>p_category then raise exception 'Record identity cannot change'; end if;
  if r.revision<>p_expected then raise exception 'Conflict: refresh before retrying' using errcode='40001'; end if;
  if r.deleted and not p_deleted then raise exception 'Deleted records cannot be resurrected'; end if;
  update public.cs_records set occurred_at=p_occurred,body=case when p_deleted then '{}'::jsonb else p_body end,private=p_private,deleted=p_deleted where id=p_id returning * into r;
 else
  if p_expected<>0 then raise exception 'Conflict: missing record' using errcode='40001'; end if;
  insert into public.cs_records(id,player_id,owner_id,sport,category,occurred_at,body,private,deleted,change_id)
  values(p_id,p_player,auth.uid(),p_sport,p_category,p_occurred,case when p_deleted then '{}'::jsonb else p_body end,p_private,p_deleted,0) returning * into r;
 end if;
 response:=jsonb_build_object('id',r.id,'revision',r.revision,'change_id',r.change_id);
 insert into cs_private.operations(account_id,operation_id,request_hash,response) values(auth.uid(),p_operation,sha256(convert_to(request::text,'UTF8')),response);
 insert into public.cs_audit(actor_id,player_account,action,entity_id) values(auth.uid(),auth.uid(),case when p_deleted then 'record_deleted' else 'record_saved' end,p_id);
 return response;
end $$;
create function public.cs_add_feedback(p_id uuid,p_connection uuid,p_record uuid,p_kind text,p_text text) returns void language plpgsql security definer set search_path='' as $$
declare c public.cs_connections; r public.cs_records; existing public.cs_feedback;
begin
 select * into c from public.cs_connections where id=p_connection for update;
 select * into r from public.cs_records where id=p_record;
 if auth.uid() is null or c.id is null or r.id is null or c.coach_account<>auth.uid() or c.state<>'active' or r.player_id<>c.player_id or r.sport<>c.sport or not cs_private.can_read(r)
 or c.capability='view' or (p_kind='contribution' and c.capability<>'contribute') then raise exception 'Feedback is not permitted'; end if;
 select * into existing from public.cs_feedback where id=p_id;
 if found then
  if existing.author_id=auth.uid() and existing.connection_id=p_connection and existing.record_id=p_record and existing.kind=p_kind and existing.text=p_text then return; end if;
  raise exception 'Feedback ID already used';
 end if;
 insert into public.cs_feedback(id,connection_id,record_id,author_id,kind,text) values(p_id,p_connection,p_record,auth.uid(),p_kind,p_text);
 insert into public.cs_audit(actor_id,player_account,coach_account,action,entity_id) values(auth.uid(),c.player_account,c.coach_account,'feedback_added',p_id);
end $$;
create function public.cs_review_feedback(p_id uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.cs_feedback f set state=case when p_approve then 'approved' else 'rejected' end
 from public.cs_connections c where f.id=p_id and c.id=f.connection_id and c.player_account=auth.uid();
 if not found then raise exception 'Only the player can review feedback'; end if;
 -- Approval records intent; applying changes to an official record requires the player's version-checked cs_put_record.
end $$;

revoke execute on all functions in schema cs_private from public,anon;
revoke execute on function public.cs_register_profile(uuid,text),public.cs_create_invitation(text,uuid,text,text),public.cs_accept_invitation(text,uuid),public.cs_set_permission(uuid,text,text[],text,timestamptz,timestamptz,boolean,text),public.cs_put_record(uuid,uuid,uuid,text,text,timestamptz,jsonb,bigint,boolean,boolean),public.cs_add_feedback(uuid,uuid,uuid,text,text),public.cs_review_feedback(uuid,boolean) from public,anon;
grant execute on function public.cs_register_profile(uuid,text),public.cs_create_invitation(text,uuid,text,text),public.cs_accept_invitation(text,uuid),public.cs_set_permission(uuid,text,text[],text,timestamptz,timestamptz,boolean,text),public.cs_put_record(uuid,uuid,uuid,text,text,timestamptz,jsonb,bigint,boolean,boolean),public.cs_add_feedback(uuid,uuid,uuid,text,text),public.cs_review_feedback(uuid,boolean) to authenticated;
commit;
