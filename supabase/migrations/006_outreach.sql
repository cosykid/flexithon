-- Venue outreach: once a location accumulates enough classified reports,
-- the draft-outreach edge function finds the business contact email and
-- drafts an advocacy email users can send from their own mail app.

create table location_outreach (
  location_id      uuid primary key references locations (id) on delete cascade,
  status           text not null default 'pending'
                   check (status in ('pending', 'drafted', 'no_email_found', 'failed')),
  business_email   text,
  email_source_url text,          -- page the email was found on (anti-hallucination proof)
  subject          text,
  body             text,
  photo_urls       jsonb not null default '[]',
  model            text,
  report_count     int not null default 0,  -- classified reports at draft time (re-draft trigger)
  updated_at       timestamptz not null default now()
);

alter table location_outreach enable row level security;

-- Clients read drafts; only the edge function (service_role) writes.
create policy "read outreach" on location_outreach
  for select to authenticated
  using (true);

-- Public bucket for photos referenced from outreach emails. Photos are copied
-- here by the service role only after a location is substantiated; public
-- URLs never expire, unlike signed ones, so links in sent emails keep working.
insert into storage.buckets (id, name, public)
values ('outreach-photos', 'outreach-photos', true)
on conflict (id) do nothing;
