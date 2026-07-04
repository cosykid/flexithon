-- Demo seed: ~30 locations around Sydney (UNSW / CBD / inner suburbs).
-- Plain INSERTs are enough — the reports_rollup trigger computes
-- locations.effective_tier exactly as it does in production.
--
-- "Rosie's Cafe (demo)" is seeded with exactly 4 partially-substantiated
-- reports: submit a 5th live on stage and watch the pin turn red.

-- Seed user (local/demo only).
-- Empty-string token columns matter: GoTrue chokes on NULLs in these fields
-- when listing users in the dashboard.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change,
  email_change_token_new, email_change_token_current,
  created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated',
  'seed@accessmap.local', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
  '', '', '', '', '',
  now(), now()
)
on conflict (id) do nothing;

do $$
declare
  seed_user uuid := '00000000-0000-0000-0000-000000000001';
  loc uuid;
  r record;
  i int;
begin
  for r in
    select * from (values
      -- name,                                  lat,        lng,       tier,            n_reports, barrier
      ('UNSW Quadrangle East Stairs',        -33.917140, 151.230780, 'substantiated', 2, 'stairs'),
      ('UNSW Science Theatre Entry',         -33.916210, 151.229900, 'substantiated', 1, 'no_ramp'),
      ('UNSW Village Green Path',            -33.915800, 151.228300, 'partial',       1, 'stairs'),
      ('Kensington High St Cafe',            -33.918900, 151.224700, 'partial',       1, 'narrow_entrance'),
      ('Randwick Junction Pharmacy',         -33.914500, 151.241300, 'substantiated', 1, 'stairs'),
      ('Coogee Beach North Steps',           -33.919600, 151.257800, 'substantiated', 3, 'stairs'),
      ('Central Station Devonshire Tunnel',  -33.883200, 151.206900, 'substantiated', 4, 'broken_lift'),
      ('Surry Hills Corner Bookshop',        -33.886100, 151.211800, 'partial',       1, 'stairs'),
      ('Crown St Vintage Store',             -33.887900, 151.213900, 'partial',       1, 'narrow_entrance'),
      ('Darlinghurst Small Bar',             -33.878900, 151.216800, 'substantiated', 2, 'stairs'),
      ('Town Hall Square Side Entry',        -33.873200, 151.206200, 'partial',       2, 'no_ramp'),
      ('QVB Basement Arcade Access',         -33.871700, 151.206600, 'partial',       1, 'broken_lift'),
      ('The Rocks Heritage Pub',             -33.859600, 151.208600, 'substantiated', 2, 'stairs'),
      ('Circular Quay West Kiosk',           -33.861500, 151.210300, 'partial',       1, 'narrow_entrance'),
      ('Newtown King St Record Store',       -33.896800, 151.179600, 'substantiated', 2, 'stairs'),
      ('Enmore Theatre Side Door',           -33.899300, 151.174200, 'partial',       1, 'no_ramp'),
      ('Glebe Point Rd Bakery',              -33.879100, 151.186200, 'substantiated', 1, 'stairs'),
      ('Broadway Shopping Upper Walk',       -33.883700, 151.194200, 'partial',       1, 'broken_lift'),
      ('Bondi Junction Mall Stairs',         -33.891400, 151.247300, 'substantiated', 2, 'stairs'),
      ('Bondi Beach South Kiosk',            -33.892900, 151.277000, 'partial',       1, 'no_ramp'),
      ('Paddington Five Ways Cafe',          -33.884600, 151.231000, 'partial',       1, 'stairs'),
      ('Oxford St Boutique',                 -33.880600, 151.222300, 'substantiated', 1, 'narrow_entrance'),
      ('Redfern Station East Exit',          -33.892200, 151.198600, 'substantiated', 3, 'broken_lift'),
      ('Green Square Espresso Bar',          -33.906400, 151.203300, 'partial',       1, 'narrow_entrance'),
      ('Maroubra Beach Pavilion',            -33.950300, 151.256900, 'partial',       1, 'no_ramp'),
      ('Kingsford Noodle House',             -33.923900, 151.227400, 'substantiated', 1, 'stairs'),
      ('Mascot Station Street Lift',         -33.926900, 151.193300, 'partial',       1, 'broken_lift'),
      ('Alexandria Cafe Courtyard',          -33.902900, 151.194000, 'substantiated', 1, 'no_ramp'),
      ('Pyrmont Harbourside Deli',           -33.869700, 151.194900, 'partial',       1, 'narrow_entrance'),
      ('Balmain Darling St Chemist',         -33.858200, 151.179800, 'substantiated', 1, 'stairs')
    ) as t(name, lat, lng, tier, n_reports, barrier)
  loop
    insert into locations (geog, name, venue_claims_accessible)
    values (
      st_setsrid(st_makepoint(r.lng, r.lat), 4326)::geography,
      r.name,
      case when r.tier = 'partial' then true else null end
    )
    returning id into loc;

    for i in 1..r.n_reports loop
      insert into reports (
        user_id, location_id, geog, description, barrier_type, status, tier,
        image_confirms_barrier, venue_claims_accessible, web_corroboration_found, ai_reasoning
      ) values (
        seed_user, loc,
        st_setsrid(st_makepoint(r.lng, r.lat), 4326)::geography,
        case r.barrier
          when 'stairs' then 'Entrance only reachable via a flight of stairs, no ramp anywhere nearby.'
          when 'no_ramp' then 'Step up into the doorway with no ramp; impossible in a wheelchair.'
          when 'narrow_entrance' then 'Doorway too narrow for my wheelchair, under 70cm.'
          when 'broken_lift' then 'Lift has been out of order for weeks; stairs are the only option.'
          else 'Inaccessible entrance.'
        end,
        r.barrier, 'classified',
        case when r.tier = 'partial' then 'partially_substantiated'::report_tier
             else 'substantiated'::report_tier end,
        true,
        case when r.tier = 'partial' then true else null end,
        r.tier <> 'partial',
        jsonb_build_object(
          'model', 'seed',
          'confidence', 'high',
          'reasoning', 'Seed data: photo clearly shows the reported barrier.',
          'tool_calls', '[]'::jsonb
        )
      );
    end loop;
  end loop;

  -- Live-promotion prop: exactly 4 partials. The 5th (submitted on stage)
  -- flips effective_tier to substantiated via the rollup trigger.
  insert into locations (geog, name, address, venue_claims_accessible)
  values (
    st_setsrid(st_makepoint(151.225900, -33.920500), 4326)::geography,
    'Rosie''s Cafe (demo)', 'Anzac Parade, Kingsford NSW', true
  )
  returning id into loc;

  for i in 1..4 loop
    insert into reports (
      user_id, location_id, geog, description, barrier_type, status, tier,
      image_confirms_barrier, venue_claims_accessible, web_corroboration_found, ai_reasoning
    ) values (
      seed_user, loc,
      st_setsrid(st_makepoint(151.225900, -33.920500), 4326)::geography,
      'Two steps at the front door, no portable ramp available when I asked.',
      'stairs', 'classified', 'partially_substantiated',
      true, true, false,
      jsonb_build_object(
        'model', 'seed', 'confidence', 'high',
        'reasoning', 'Photo shows front-door steps, but the venue claims wheelchair accessibility online.',
        'tool_calls', '[]'::jsonb
      )
    );
  end loop;
end $$;
