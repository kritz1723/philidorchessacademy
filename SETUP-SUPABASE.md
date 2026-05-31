# Parent Portal — Supabase Setup (≈5 minutes, free)

The parent login/signup uses **Supabase Auth**. Supabase securely stores
passwords for you (hashed with bcrypt, server-side) — this site never sees
or stores raw passwords. Free tier, no credit card.

## 1. Create a project
1. Go to <https://supabase.com> → **Start your project** → sign in with GitHub.
2. **New project** → give it a name (e.g. `philidor-parents`) → choose a
   region close to you → set a database password (save it somewhere) → **Create**.
3. Wait ~1 minute for it to provision.

## 2. Create the database table
1. Left sidebar → **SQL Editor** → **New query**.
2. Open `supabase/schema.sql` from this repo, copy everything, paste it in.
3. Click **Run**. You should see "Success".

## 3. Copy your API keys into the site
1. Left sidebar → **Project Settings** (gear) → **API**.
2. Copy these two values:
   - **Project URL** (looks like `https://abcd1234.supabase.co`)
   - **anon public** key (a long string)
3. Open `js/supabase-config.js` and paste them in:
   ```js
   window.SUPABASE_URL = "https://abcd1234.supabase.co";
   window.SUPABASE_ANON_KEY = "eyJhbGciOi...your-anon-key...";
   ```
   > The **anon** key is meant to be public — it's safe in frontend code.
   > NEVER paste the `service_role` secret key here.
4. Commit & push the change.

## 4. (Recommended) Decide on email confirmation
By default Supabase emails a confirmation link before a new account can sign in.
- **Project Settings → Authentication → Providers → Email**
  - Leave **Confirm email** ON for real security (parents click a link in their inbox).
  - Turn it OFF for instant signup→dashboard if you're just testing.

## 5. Allow your website's address
**Project Settings → Authentication → URL Configuration**
- Add your live site URL (e.g. `https://kritz1723.github.io`) to **Site URL**
  and **Redirect URLs** so confirmation links work.

## Done!
Visit `parent-login.html`, create an account, and you'll land on
`parent-dashboard.html`. New parents appear under **Authentication → Users**
in Supabase, and their profile details under **Table Editor → profiles**.

---

### How security works here (plain English)
- Passwords live only inside Supabase's protected `auth.users` table, bcrypt-hashed.
- The `profiles` table holds non-secret details (name, child, phone).
- **Row Level Security** policies (in `schema.sql`) mean each logged-in parent
  can read/edit only their own row — even though the anon key is public.
