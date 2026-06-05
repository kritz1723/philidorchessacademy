-- ============================================================
--  Philidor Chess Academy — Seed the "Basic" topic
--  Creates a topic named "Basic" and attaches the four Chess
--  Basics pages (in materials/basics/) as its materials.
--  Run AFTER topics-schema.sql. Safe to run multiple times.
--  Supabase -> SQL Editor -> paste -> Run.
--
--  After running: Admin -> Topics -> "Basic" -> assignments ->
--  tick the parents/children (or "Assign to all parents").
-- ============================================================
do $$
declare tid uuid;
begin
  -- find or create the topic
  select id into tid from public.topics where name = 'Basic' limit 1;
  if tid is null then
    insert into public.topics (name, description, assign_all, sort_order)
    values ('Basic', 'Chess fundamentals — start here.', false, 0)
    returning id into tid;
  end if;

  -- attach the four pages as materials (idempotent by title)
  insert into public.topic_materials (topic_id, title, url, sort_order)
  select tid, x.title, x.url, x.ord
  from (values
    ('Overview',            'materials/basics/basics-index.html',    0),
    ('Piece Values',        'materials/basics/basics-values.html',   1),
    ('Good & Bad Trades',   'materials/basics/basics-trades.html',   2),
    ('Castling',            'materials/basics/basics-castling.html', 3)
  ) as x(title, url, ord)
  where not exists (
    select 1 from public.topic_materials m
    where m.topic_id = tid and m.title = x.title
  );
end $$;
