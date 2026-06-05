-- ============================================================
--  Philidor Chess Academy — Link each child to ChessLang
--  Stores the ChessLang "student report" UUID for each child so an
--  importer/bot can pull that kid's stats and upsert them into
--  student_stats. Run anytime. Safe to run multiple times.
--
--  The UUID is the one in the ChessLang report URL, e.g.
--    app.chesslang.com/app/reports/student/<THIS-UUID>/overall
-- ============================================================
alter table public.children
  add column if not exists chesslang_id text;

create index if not exists children_chesslang_idx
  on public.children(chesslang_id) where chesslang_id is not null;
