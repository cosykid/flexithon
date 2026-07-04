-- RLS: anonymous-auth users are role `authenticated`.
-- Clients may only insert; all updates/deletes happen via service_role (edge function).
alter table reports enable row level security;
alter table locations enable row level security;

create policy "insert own reports" on reports
  for insert to authenticated
  with check (user_id = auth.uid());

create policy "read visible reports" on reports
  for select to authenticated
  using (
    user_id = auth.uid()
    or (status = 'classified' and tier in ('partially_substantiated', 'substantiated'))
  );

create policy "read locations" on locations
  for select to authenticated
  using (true);

create policy "insert locations" on locations
  for insert to authenticated
  with check (true);

-- Storage: run after creating the private `report-photos` bucket.
-- On hosted Supabase the migration role may not own storage.objects; if so,
-- create these two policies via the dashboard instead (Storage → Policies).
do $$
begin
  create policy "upload own photos" on storage.objects
    for insert to authenticated
    with check (
      bucket_id = 'report-photos'
      and (storage.foldername(name))[1] = auth.uid()::text
    );

  create policy "read report photos" on storage.objects
    for select to authenticated
    using (bucket_id = 'report-photos');
exception when insufficient_privilege then
  raise notice 'storage.objects policies skipped — create them in the dashboard';
end $$;
