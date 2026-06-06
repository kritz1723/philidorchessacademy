# ChessLang bot — backlog

Known items to revisit later (not blocking the working sync).

## 1. Quiz fields not captured yet
**Status:** open · low priority (deferred 2026-06-06 per request)

**Symptom:** `quizzes_completed`, `quizzes_total`, `problems_solved`,
`problems_total`, `quiz_points`, `quiz_time_taken` never appear in the
parsed output — even with the date range widened to 2020-01-01 → today.

**Why (likely):**
- The linked kids currently have **0 quiz activity** (the Quiz tab shows
  `0/0` everywhere), so there's nothing meaningful to capture; and
- the **detailed `/quiz` tab** we scrape may not render the summary
  labels the regexes expect (it shows a chart/empty state), whereas the
  **`/overall` tab** *does* list them: "Total quizzes completed", "Total
  problems solved", "Total time taken", "Total points scored".

**Proposed fix (when we revisit):**
- Parse quiz summary from the **`/overall`** tab (same approach we used
  for the Classroom summary), not the detailed `/quiz` tab.
- Verify the exact label wording against a student who actually **has**
  quiz activity (current test kids are all 0/0), then tighten the regexes.

**Where:** `tools/chesslang-bot/sync.js`, `scrapeStudent()` → Quiz block.

## 2. (Possible) Export-based sync — all students in one shot
**Status:** open · waiting on a sample export file from ChessLang.
Switching from per-kid page scraping to parsing the ChessLang **Export**
would cover all students without linking each kid's UUID. Needs one
sample export file to determine columns + the student-name mapping.
