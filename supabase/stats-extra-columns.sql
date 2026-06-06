-- ============================================================
--  Philidor Chess Academy — extra ChessLang stats columns
--  Adds the richer per-student fields available on ChessLang's
--  individual report tabs (medals, class breakdown, results by
--  colour, tournament podium). Run anytime. Idempotent.
--  Supabase -> SQL Editor -> paste -> Run.
-- ============================================================
alter table public.student_stats
  -- medals (Classroom tab)
  add column if not exists medals_gold       int default 0,
  add column if not exists medals_silver     int default 0,
  add column if not exists medals_bronze     int default 0,
  -- class breakdown (Classroom tab)
  add column if not exists classes_invited   int,
  add column if not exists individual_classes int,
  add column if not exists group_classes     int,
  -- results by colour (Game Area tab)
  add column if not exists white_games  int,
  add column if not exists white_wins   int,
  add column if not exists white_losses int,
  add column if not exists white_draws  int,
  add column if not exists black_games  int,
  add column if not exists black_wins   int,
  add column if not exists black_losses int,
  add column if not exists black_draws  int,
  -- tournament podium (Tournament tab)
  add column if not exists tournaments_1st int default 0,
  add column if not exists tournaments_2nd int default 0,
  add column if not exists tournaments_3rd int default 0;
