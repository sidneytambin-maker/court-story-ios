-- Explicit sporting fields only: never copy the full court/plan/score object.
do $$ declare constraint_name text; begin
 select conname into constraint_name from pg_constraint
 where conrelid='public.cs_records'::regclass and contype='c'
 and pg_get_constraintdef(oid) like '%body - ARRAY%';
 if constraint_name is null then raise exception 'Sporting body allowlist constraint missing'; end if;
 execute format('alter table public.cs_records drop constraint %I',constraint_name);
end $$;
alter table public.cs_records add constraint cs_records_sporting_body_fields
check(body - array['title','result','score','duration_minutes','focus','text','status','matchType','matchFormat','yourSetsWon','opponentSetsWon','aces','doubleFaults','winners','unforcedErrors','hadTiebreak','tiebreakScore','tournamentID','trainingSessionID','finalResult','matchesPlayed','format','stageReached','finishingPosition','endDate','customScoreSummary','surface','sessionType','planObjective','planDrills','planEquipment','planSuccessMeasure'] = '{}'::jsonb);
