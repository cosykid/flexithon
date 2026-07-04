-- Rollup + auto-promotion. PROMOTION_THRESHOLD = 5 partially-substantiated
-- reports at one location promote it to substantiated.
-- Lives in the DB (not the edge function) so it is atomic under concurrent
-- classifications and fires for seed data too.
create or replace function refresh_location_rollup() returns trigger as $$
begin
  update locations l set
    partial_count = s.pc,
    substantiated_count = s.sc,
    effective_tier = case
      when s.sc > 0 or s.pc >= 5 then 'substantiated'::report_tier
      when s.pc > 0 then 'partially_substantiated'::report_tier
      else null
    end
  from (
    select
      count(*) filter (where tier = 'partially_substantiated' and status = 'classified') as pc,
      count(*) filter (where tier = 'substantiated' and status = 'classified') as sc
    from reports
    where location_id = new.location_id
  ) s
  where l.id = new.location_id;
  return new;
end;
$$ language plpgsql security definer;

create trigger reports_rollup
  after insert or update of tier, status on reports
  for each row execute function refresh_location_rollup();
