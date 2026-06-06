# "Sync stats now" — one-time setup

Lets the Admin page trigger the ChessLang sync on demand (button in
**Admin → Student Stats → "Sync from ChessLang now"**). The GitHub token
lives only in Supabase as a secret — never in the browser.

## 1. Create a GitHub token (fine-grained)
GitHub → Settings → Developer settings → **Fine-grained tokens** → Generate:
- **Resource owner:** `kritz1723`
- **Repository access → Only select repositories →** `philidorchessacademy`
- **Permissions → Repository → Actions → Read and write**
- Generate and copy the `github_pat_…` token.

## 2. Add it as a Supabase secret
Supabase → **Edge Functions → Secrets** → add:

| Name | Value |
| --- | --- |
| `GH_DISPATCH_TOKEN` | the `github_pat_…` token |

(`GH_OWNER`, `GH_REPO`, `GH_WORKFLOW`, `GH_BRANCH` default to this repo;
override only if they change. `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`
are injected automatically.)

## 3. Deploy the function
**Dashboard:** Edge Functions → **Create a function** → name it exactly
`trigger-sync` → paste `supabase/functions/trigger-sync/index.ts` → Deploy.

**CLI:** `supabase functions deploy trigger-sync`

Keep JWT verification on (default); the function also re-checks the
caller is an admin.

## Use it
Admin → **Student Stats** → **Sync from ChessLang now**. It starts the
nightly workflow immediately; stats refresh in ~1–2 minutes. (The bot
still also runs automatically every night.)
