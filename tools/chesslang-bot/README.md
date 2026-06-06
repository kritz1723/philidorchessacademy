# ChessLang → Supabase stats bot

Logs into ChessLang on a schedule, reads each linked child's report,
and updates `student_stats` so the parent dashboard stays fresh — no
manual data entry.

## How it fits together
1. Each child has a **`chesslang_id`** (the UUID in the ChessLang report
   URL). Set it in **Admin → Stats → pick child → ChessLang link**.
2. This bot (`sync.js`, Playwright) logs in, visits each child's
   `classroom / gamearea / quiz / tournament` report tabs, parses the
   numbers, and **upserts** them into `student_stats` (only fields it
   finds — it never blanks out existing data).
3. It runs nightly via `.github/workflows/chesslang-sync.yml` (and can be
   run on demand).

## One-time setup

### 1. Add GitHub Actions secrets
Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
| --- | --- |
| `SUPABASE_URL` | `https://kewukhytqajlqdlxjuip.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase → Settings → API → **service_role** key (secret!) |
| `CHESSLANG_EMAIL` | your ChessLang login email |
| `CHESSLANG_PASSWORD` | your ChessLang password |

> The service_role key and your ChessLang password live **only** in
> GitHub Secrets — never in the code or anywhere public.

### 2. Link the kids
Run `supabase/chesslang-mapping.sql`, then set each child's ChessLang ID
in Admin (the UUID from `app.chesslang.com/app/reports/student/<UUID>/overall`).

### 3. First run = dry run
Actions tab → **ChessLang stats sync** → **Run workflow** → tick
**Dry run** → Run. Open the logs: each child prints the values parsed.
If they look right, run again without dry-run to write them. After that
it runs automatically every night.

If login fails or values are blank, the run uploads **debug screenshots**
(Actions run → Artifacts → `chesslang-debug`) so the login selectors or
label regexes in `sync.js` can be tuned in one pass.

## Local test (optional)
```bash
cd tools/chesslang-bot
npm install && npx playwright install chromium
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
CHESSLANG_EMAIL=... CHESSLANG_PASSWORD=... DRY_RUN=1 node sync.js
```

## Notes / limits
- If ChessLang login uses **2FA / OTP**, a headless bot can't pass it —
  tell me and we'll switch to the upload-export approach.
- Stats reflect whatever **date range** ChessLang shows by default. If you
  need a fixed range (e.g. all-time), we can set the date pickers in the
  bot — ask and I'll add it.
