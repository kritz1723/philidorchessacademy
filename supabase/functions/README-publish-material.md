# "Publish material to the website" — one-time setup

This Edge Function lets the **Admin → Topics** page publish an HTML page
straight into the repo (GitHub Pages then serves it) and assign it to
parents — no code change, no manual commit.

The GitHub token lives **only** in Supabase as a secret. It is never sent
to the browser.

## 1. Create a GitHub token (fine-grained, least-privilege)

1. GitHub → **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**.
2. **Resource owner:** `kritz1723`.
3. **Repository access → Only select repositories →** `philidorchessacademy`.
4. **Permissions → Repository permissions → Contents → Read and write.**
   (That's the only permission needed.)
5. Set an expiry you're comfortable with, generate, and **copy the token**
   (starts with `github_pat_…`).

## 2. Add the token as a Supabase secret

**Dashboard:** Supabase → **Edge Functions → Secrets** (Manage secrets) →
add:

| Name           | Value                          |
| -------------- | ------------------------------ |
| `GITHUB_TOKEN` | the `github_pat_…` you copied  |

`GH_OWNER`, `GH_REPO`, `GH_BRANCH` default to
`kritz1723` / `philidorchessacademy` / `main` — only add them if those
ever change. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected
automatically.

(Or with the CLI: `supabase secrets set GITHUB_TOKEN=github_pat_xxx`.)

## 3. Deploy the function

**Option A — Supabase Dashboard (no tools needed):**
Edge Functions → **Create a function** → name it exactly
`publish-material` → paste the contents of
`supabase/functions/publish-material/index.ts` → **Deploy**.

**Option B — Supabase CLI:**
```bash
supabase login
supabase link --project-ref kewukhytqajlqdlxjuip
supabase functions deploy publish-material
```

Keep JWT verification **on** (the default) — the function also re-checks
that the caller is an admin.

## 4. Use it

Admin → **Topics** → pick a topic → **Manage** → in *Add material*, use
the **"Publish a page to the website"** file picker, choose your `.html`
file, set a title, **Add material** → it commits, publishes (~1 min for
Pages to rebuild), and is attached to the topic. Then assign the topic to
parents as usual.

> Published pages live at `materials/published/…` and are **public URLs**
> (anyone with the link can open them). For private, parent-only files use
> the **upload** option instead, which stores them privately and serves
> short-lived signed links.
