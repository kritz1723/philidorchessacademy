// ============================================================
//  Philidor Chess Academy — "Sync stats now" trigger
//  Supabase Edge Function. The Admin page calls this to kick off
//  the ChessLang sync GitHub Action on demand.
//
//  Verifies the caller is an admin, then dispatches the
//  chesslang-sync.yml workflow via the GitHub API. The GitHub token
//  lives ONLY here as a secret (GH_DISPATCH_TOKEN) — never in the
//  browser. See README-trigger-sync.md for setup.
// ============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const TOKEN = Deno.env.get("GH_DISPATCH_TOKEN");
    const OWNER = Deno.env.get("GH_OWNER") || "kritz1723";
    const REPO = Deno.env.get("GH_REPO") || "philidorchessacademy";
    const WORKFLOW = Deno.env.get("GH_WORKFLOW") || "chesslang-sync.yml";
    const BRANCH = Deno.env.get("GH_BRANCH") || "main";

    if (!TOKEN) return json({ ok: false, error: "Server missing GH_DISPATCH_TOKEN secret." });

    // ---- verify the caller is a signed-in admin ----
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return json({ ok: false, error: "Not signed in." });
    const admin = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: userData, error: uErr } = await admin.auth.getUser(token);
    if (uErr || !userData?.user) return json({ ok: false, error: "Invalid session." });
    const { data: adminRow } = await admin.from("admins").select("user_id").eq("user_id", userData.user.id).maybeSingle();
    if (!adminRow) return json({ ok: false, error: "Admins only." });

    // ---- dispatch the workflow ----
    const body = await req.json().catch(() => ({}));
    const dry = body && body.dry_run ? "true" : "false";
    const res = await fetch(
      `https://api.github.com/repos/${OWNER}/${REPO}/actions/workflows/${WORKFLOW}/dispatches`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${TOKEN}`,
          "Accept": "application/vnd.github+json",
          "User-Agent": "pca-sync-trigger",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ ref: BRANCH, inputs: { dry_run: dry } }),
      },
    );
    if (res.status === 204) return json({ ok: true });
    return json({ ok: false, error: "GitHub dispatch failed (" + res.status + ")", detail: await res.text() });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e) });
  }
});
