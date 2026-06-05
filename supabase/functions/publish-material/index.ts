// ============================================================
//  Philidor Chess Academy — "Publish material to the website"
//  Supabase Edge Function.
//
//  The Admin page sends an HTML page (base64). This function:
//    1. verifies the caller is an admin,
//    2. commits the file into the GitHub repo (GitHub Pages then
//       publishes it automatically),
//    3. appends it to materials/manifest.json so it also shows up
//       in the "Pick a material page" dropdown next time.
//
//  The GitHub token lives ONLY here (as a secret), never in the
//  browser. See supabase/functions/README-publish-material.md for
//  one-time setup.
// ============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

// UTF-8 safe base64 (titles/JSON may contain non-Latin1 characters).
function b64encodeUtf8(str: string): string {
  const bytes = new TextEncoder().encode(str);
  let bin = "";
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin);
}
function b64decodeUtf8(b64: string): string {
  const bin = atob(b64.replace(/\n/g, ""));
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

const GH_API = "https://api.github.com";
function ghHeaders(token: string) {
  return {
    "Authorization": `Bearer ${token}`,
    "Accept": "application/vnd.github+json",
    "User-Agent": "pca-publisher",
    "Content-Type": "application/json",
  };
}
function ghUrl(owner: string, repo: string, path: string) {
  // keep slashes in the path un-encoded
  const enc = path.split("/").map(encodeURIComponent).join("/");
  return `${GH_API}/repos/${owner}/${repo}/contents/${enc}`;
}

async function ghGet(
  owner: string,
  repo: string,
  path: string,
  branch: string,
  token: string,
) {
  const r = await fetch(`${ghUrl(owner, repo, path)}?ref=${branch}`, {
    headers: ghHeaders(token),
  });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error("GitHub read failed: " + (await r.text()));
  return await r.json();
}

async function ghPut(
  owner: string,
  repo: string,
  path: string,
  body: Record<string, unknown>,
  token: string,
) {
  return await fetch(ghUrl(owner, repo, path), {
    method: "PUT",
    headers: ghHeaders(token),
    body: JSON.stringify(body),
  });
}

async function appendManifest(
  owner: string,
  repo: string,
  branch: string,
  token: string,
  entry: { title: string; url: string },
) {
  const existing = await ghGet(owner, repo, "materials/manifest.json", branch, token);
  let data: { materials?: Array<{ title: string; url: string }> } = { materials: [] };
  let sha: string | undefined;
  if (existing && existing.content) {
    sha = existing.sha;
    try {
      data = JSON.parse(b64decodeUtf8(existing.content));
    } catch (_e) {
      data = { materials: [] };
    }
    if (!Array.isArray(data.materials)) data.materials = [];
  }
  data.materials!.push(entry);
  const put = await ghPut(owner, repo, "materials/manifest.json", {
    message: `Add material to manifest: ${entry.title}`,
    content: b64encodeUtf8(JSON.stringify(data, null, 2)),
    branch,
    sha,
  }, token);
  if (!put.ok) throw new Error("manifest update failed: " + (await put.text()));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const GITHUB_TOKEN = Deno.env.get("GITHUB_TOKEN");
    const OWNER = Deno.env.get("GH_OWNER") || "kritz1723";
    const REPO = Deno.env.get("GH_REPO") || "philidorchessacademy";
    const BRANCH = Deno.env.get("GH_BRANCH") || "main";

    if (!GITHUB_TOKEN) {
      return json({ ok: false, error: "Server missing GITHUB_TOKEN secret." });
    }

    // ---- verify the caller is a signed-in admin ----
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) return json({ ok: false, error: "Not signed in." });

    const admin = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: userData, error: uErr } = await admin.auth.getUser(token);
    if (uErr || !userData?.user) {
      return json({ ok: false, error: "Invalid session." });
    }
    const { data: adminRow } = await admin
      .from("admins")
      .select("user_id")
      .eq("user_id", userData.user.id)
      .maybeSingle();
    if (!adminRow) return json({ ok: false, error: "Admins only." });

    // ---- read payload ----
    const body = await req.json().catch(() => ({}));
    const title = String(body.title || "").trim();
    let filename = String(body.filename || "").trim();
    const contentBase64 = String(body.contentBase64 || "");
    const updateManifest = body.updateManifest !== false;
    if (!contentBase64) return json({ ok: false, error: "Missing file content." });

    // sanitize filename -> materials/published/<timestamp>_<name>
    filename = filename.replace(/[^\w.\-]+/g, "_").replace(/^_+|_+$/g, "");
    if (!filename) filename = "material.html";
    if (!/\.[a-z0-9]+$/i.test(filename)) filename += ".html";
    const path = `materials/published/${Date.now()}_${filename}`;

    // ---- commit the file (creates a new file; no sha needed) ----
    const put = await ghPut(OWNER, REPO, path, {
      message: `Publish material: ${title || filename}`,
      content: contentBase64,
      branch: BRANCH,
    }, GITHUB_TOKEN);
    if (!put.ok) {
      return json({
        ok: false,
        error: "GitHub commit failed",
        detail: await put.text(),
      });
    }

    // ---- best-effort: add to manifest dropdown ----
    if (updateManifest) {
      try {
        await appendManifest(OWNER, REPO, BRANCH, GITHUB_TOKEN, {
          title: title || filename,
          url: path,
        });
      } catch (_e) {
        // non-fatal: the page is published either way
      }
    }

    return json({ ok: true, url: path });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e) });
  }
});
