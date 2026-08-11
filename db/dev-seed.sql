insert into organizations (id, name, email)
values ('00000000-0000-4000-8000-000000000001', 'Pilot Demo SRL', 'demo@pilot.local')
on conflict (id) do update set
  name = excluded.name,
  email = excluded.email,
  updated_at = now();
