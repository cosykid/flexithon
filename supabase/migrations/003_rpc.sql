-- Viewport query: one row per visible location; the Flutter cluster plugin
-- does the visual clustering client-side.
create or replace function points_in_bbox(
  min_lng float8, min_lat float8, max_lng float8, max_lat float8
) returns table (
  location_id  uuid,
  lat          float8,
  lng          float8,
  tier         report_tier,
  name         text,
  report_count int
) language sql stable as $$
  select
    l.id,
    st_y(l.geog::geometry),
    st_x(l.geog::geometry),
    l.effective_tier,
    l.name,
    (l.partial_count + l.substantiated_count)::int
  from locations l
  where l.effective_tier is not null
    and l.geog && st_makeenvelope(min_lng, min_lat, max_lng, max_lat, 4326)::geography
  limit 500;
$$;

-- Find-or-create the location a new report attaches to.
-- Tagged venue: upsert on place_ref. Untagged: fresh location at the GPS point.
create or replace function upsert_location(
  p_lat float8, p_lng float8,
  p_place_ref text default null,
  p_name text default null,
  p_address text default null
) returns uuid language plpgsql security definer as $$
declare
  loc_id uuid;
  pt geography := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
begin
  if p_place_ref is not null then
    insert into locations (geog, place_ref, name, address)
    values (pt, p_place_ref, p_name, p_address)
    on conflict (place_ref) do update set name = coalesce(locations.name, excluded.name)
    returning id into loc_id;
  else
    -- Untagged report: reuse the nearest existing location within 30 m so
    -- repeat reports at the same spot pile onto one pin (and the >=5-partial
    -- promotion can actually trigger).
    select id into loc_id
    from locations
    where st_dwithin(geog, pt, 30)
    order by st_distance(geog, pt)
    limit 1;

    if loc_id is null then
      insert into locations (geog, name)
      values (pt, p_name)
      returning id into loc_id;
    end if;
  end if;
  return loc_id;
end;
$$;
