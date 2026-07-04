-- Per-claim source links for AI verification. One row per link cited by the
-- verifier; the app fetches the URL from here at click time and opens it.
create table report_sources (
  id         uuid primary key default gen_random_uuid(),
  report_id  uuid not null references reports (id) on delete cascade,
  url        text not null,
  title      text,
  claim      text,        -- which verified claim this source supports
  position   int not null default 0,  -- citation order from the verdict
  created_at timestamptz not null default now()
);

create index report_sources_report_idx on report_sources (report_id);

-- Same visibility as the parent report; writes only via the service role.
alter table report_sources enable row level security;

create policy "read sources of visible reports" on report_sources
  for select to authenticated
  using (
    exists (
      select 1 from reports r
      where r.id = report_id
        and (
          r.user_id = auth.uid()
          or (r.status = 'classified'
              and r.tier in ('partially_substantiated', 'substantiated'))
        )
    )
  );
