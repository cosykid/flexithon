-- AccessMap schema: locations (venue/spot rollups) + reports (individual submissions)
create extension if not exists postgis;

create type report_tier as enum ('unsubstantiated', 'partially_substantiated', 'substantiated');
create type report_status as enum ('pending', 'classified', 'rejected');

create table locations (
  id                      uuid primary key default gen_random_uuid(),
  geog                    geography(point, 4326) not null,
  place_ref               text unique,          -- Google place_id; null if untagged spot
  name                    text,
  address                 text,
  venue_claims_accessible boolean,              -- cached from Google Places accessibilityOptions
  partial_count           int not null default 0,
  substantiated_count     int not null default 0,
  effective_tier          report_tier,          -- pin colour source, includes >=5 auto-promotion
  created_at              timestamptz not null default now()
);

create index locations_geog_idx on locations using gist (geog);

create table reports (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null references auth.users (id),
  location_id             uuid not null references locations (id),
  geog                    geography(point, 4326) not null,  -- exact GPS of this report
  photo_path              text,                 -- storage path in report-photos bucket
  description             text not null,
  barrier_type            text,                 -- set by AI: stairs|no_ramp|narrow_entrance|broken_lift|other
  status                  report_status not null default 'pending',
  tier                    report_tier,          -- null until classified
  image_confirms_barrier  boolean,
  venue_claims_accessible boolean,
  web_corroboration_found boolean,
  ai_reasoning            jsonb,                -- {model, reasoning, tool_calls, confidence}
  retry_count             int not null default 0,
  created_at              timestamptz not null default now()
);

create index reports_location_idx on reports (location_id);
create index reports_user_idx on reports (user_id);
create index reports_status_idx on reports (status) where status = 'pending';
