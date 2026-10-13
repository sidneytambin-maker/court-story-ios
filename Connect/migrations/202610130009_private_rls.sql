-- Defence in depth for private queues and invitation receipts.
-- Matches the explicit RLS added during the initial dashboard deployment.
begin;
alter table cs_private.invitations enable row level security;
alter table cs_private.operations enable row level security;
alter table cs_private.push_devices enable row level security;
alter table cs_private.push_deliveries enable row level security;
revoke all on all tables in schema cs_private from public, anon, authenticated;
commit;
