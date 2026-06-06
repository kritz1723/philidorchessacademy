/* ============================================================
 * Philidor Chess Academy — ChessLang -> Supabase stats sync
 *
 * Logs into ChessLang, reads each linked child's report tabs, and
 * upserts the numbers into public.student_stats. Designed to run on a
 * schedule (GitHub Actions). Credentials come ONLY from environment
 * secrets — never hard-code them.
 *
 * Required env:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 *   CHESSLANG_EMAIL, CHESSLANG_PASSWORD
 * Optional env:
 *   CHESSLANG_LOGIN_URL   (default https://app.chesslang.com/)
 *   CHESSLANG_BASE        (default https://app.chesslang.com/app/reports/student)
 *   DRY_RUN=1             (parse + log only, no DB writes)
 *
 * Parsing is label-based (reads the visible text), so it survives most
 * layout tweaks. If ChessLang changes wording, adjust the regexes below.
 * ============================================================ */
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const { createClient } = require('@supabase/supabase-js');

const {
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
  CHESSLANG_EMAIL,
  CHESSLANG_PASSWORD,
  CHESSLANG_LOGIN_URL = 'https://app.chesslang.com/',
  CHESSLANG_BASE = 'https://app.chesslang.com/app/reports/student',
  DATE_FROM = '2026-05-01',
  DATE_TO = '',
  DRY_RUN = '',
} = process.env;

// ChessLang shows dates as DD-MMM-YYYY (e.g. 01-May-2026).
var MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
function fmtDate(iso) {
  var d = iso ? new Date(iso) : new Date();
  if (isNaN(d)) d = new Date();
  return String(d.getDate()).padStart(2, '0') + '-' + MONTHS[d.getMonth()] + '-' + d.getFullYear();
}
var DATE_FROM_STR = DATE_FROM ? fmtDate(DATE_FROM) : null;
var DATE_TO_STR = fmtDate(DATE_TO || undefined); // blank => today

const DEBUG_DIR = path.join(__dirname, 'debug');
function ensureDebug() { try { fs.mkdirSync(DEBUG_DIR, { recursive: true }); } catch (_e) {} }
async function shot(page, name) {
  try { ensureDebug(); await page.screenshot({ path: path.join(DEBUG_DIR, name + '.png'), fullPage: true }); }
  catch (_e) {}
}

function requireEnv() {
  var missing = [];
  if (!SUPABASE_URL) missing.push('SUPABASE_URL');
  if (!SUPABASE_SERVICE_ROLE_KEY) missing.push('SUPABASE_SERVICE_ROLE_KEY');
  if (!CHESSLANG_EMAIL) missing.push('CHESSLANG_EMAIL');
  if (!CHESSLANG_PASSWORD) missing.push('CHESSLANG_PASSWORD');
  if (missing.length) { console.error('Missing env: ' + missing.join(', ')); process.exit(1); }
}

// ---- text parsing helpers ----
function num(text, re, idx) {
  var m = text.match(re); idx = idx || 1;
  if (!m || m[idx] == null) return null;
  var n = Number(String(m[idx]).replace(/,/g, ''));
  return isNaN(n) ? null : n;
}
function str(text, re, idx) {
  var m = text.match(re); idx = idx || 1;
  return (m && m[idx] != null) ? m[idx].trim() : null;
}
// drop null/undefined keys so we never clobber existing data with blanks
function compact(obj) {
  var out = {};
  Object.keys(obj).forEach(function (k) { if (obj[k] !== null && obj[k] !== undefined) out[k] = obj[k]; });
  return out;
}

// Log the page's form structure into the run logs (so we can refine
// selectors without needing the screenshot artifact).
async function dumpForm(page) {
  try {
    console.log('  page url:', page.url());
    console.log('  page title:', await page.title());
    var info = await page.evaluate(function () {
      function d(el) { return { tag: el.tagName.toLowerCase(), type: el.type || '', name: el.name || '', id: el.id || '', placeholder: el.placeholder || '', autocomplete: el.getAttribute('autocomplete') || '' }; }
      var inputs = [].slice.call(document.querySelectorAll('input')).map(d);
      var btns = [].slice.call(document.querySelectorAll('button, a, [role=button]')).slice(0, 40)
        .map(function (b) { return { tag: b.tagName.toLowerCase(), type: b.getAttribute('type') || '', text: (b.innerText || b.value || '').trim().slice(0, 40) }; })
        .filter(function (b) { return b.text || b.type; });
      var frames = [].slice.call(document.querySelectorAll('iframe')).map(function (f) { return f.src || '(no src)'; });
      return { inputs: inputs, buttons: btns, iframes: frames };
    });
    console.log('  inputs:', JSON.stringify(info.inputs));
    console.log('  buttons:', JSON.stringify(info.buttons));
    console.log('  iframes:', JSON.stringify(info.iframes));
  } catch (e) { console.warn('  dumpForm failed: ' + (e && e.message || e)); }
}

async function login(page) {
  // ChessLang is a SPA with long-lived connections, so 'networkidle'
  // never settles — wait for DOM + the actual login field instead.
  var emailSel = 'input[type=email], input[name=email], input[name=username], input[autocomplete="username"], input[placeholder*="mail" i], input[placeholder*="user" i]';
  var passSel = 'input[type=password], input[name=password], input[autocomplete="current-password"]';
  try {
    await page.goto(CHESSLANG_LOGIN_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(3500);
    var found = await page.waitForSelector(emailSel, { timeout: 25000 }).then(function () { return true; }).catch(function () { return false; });
    if (!found) {
      console.error('  Could not find the login/email field. Page structure:');
      await dumpForm(page);
      await shot(page, 'login-error');
      throw new Error('Login/email field not found — see the logged inputs/buttons above to refine the selector.');
    }
    await page.fill(emailSel, CHESSLANG_EMAIL);
    await page.fill(passSel, CHESSLANG_PASSWORD);
    var btn = page.locator('button[type=submit], button:has-text("Login"), button:has-text("Log in"), button:has-text("Sign in")').first();
    if (await btn.count()) { await btn.click(); } else { await page.keyboard.press('Enter'); }
    // Wait for the login field to go away (i.e. we navigated past login).
    await page.waitForSelector(passSel, { state: 'detached', timeout: 45000 }).catch(function () {});
    await page.waitForTimeout(2500);
    if (await page.locator(passSel).count()) {
      await shot(page, 'login-failed');
      throw new Error('Login did not complete — check credentials or the login selectors (see login-failed.png).');
    }
  } catch (e) {
    await shot(page, 'login-error');
    throw e;
  }
}

// Best-effort: set the report's date range. ChessLang looks like an
// Ant Design app (RangePicker = two .ant-picker-input inputs). If the
// markup differs, we log and fall back to ChessLang's default range.
async function setDateRange(page) {
  if (!DATE_FROM_STR && !DATE_TO_STR) return;
  try {
    var inputs = page.locator('.ant-picker-input input');
    var n = await inputs.count();
    if (n >= 2) {
      if (DATE_FROM_STR) { await inputs.nth(0).click(); await inputs.nth(0).fill(DATE_FROM_STR); await page.keyboard.press('Enter'); }
      if (DATE_TO_STR)   { await inputs.nth(1).click(); await inputs.nth(1).fill(DATE_TO_STR);   await page.keyboard.press('Enter'); }
      await page.keyboard.press('Escape');
      await page.waitForTimeout(1200);
      console.log('  date range set ' + DATE_FROM_STR + ' → ' + DATE_TO_STR);
      return;
    }
    console.warn('  date-range inputs (.ant-picker-input) not found — using ChessLang default range');
  } catch (e) { console.warn('  date range set failed: ' + (e && e.message || e)); }
}

async function tabText(page, uuid, tab) {
  var url = CHESSLANG_BASE + '/' + uuid + '/' + tab;
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForTimeout(2500); // let the SPA fetch + render numbers
  await setDateRange(page);
  return await page.evaluate(function () { return document.body.innerText; });
}

async function scrapeStudent(page, uuid) {
  var stats = {};

  // ----- Classroom (summary lives on the Overall tab) -----
  var c = await tabText(page, uuid, 'overall');
  stats.attendance_pct = num(c, /Attendance\s*([\d.]+)\s*%/i);
  var cls = c.match(/Total classes attended\s*(\d+)\s*\/\s*(\d+)/i);
  if (cls) { stats.classes_attended = Number(cls[1]); stats.classes_total = Number(cls[2]); }
  stats.hours_in_classroom = num(c, /Total hours spent in classroom\s*([\d.]+)/i);
  stats.leaderboard_points = num(c, /Total leaderboard points\s*([\d,]+)/i);

  // ----- Game Area -----
  var g = await tabText(page, uuid, 'gamearea');
  stats.games_played = num(g, /Total games\s*(\d+)/i);
  stats.wins = num(g, /Total wins\s*(\d+)/i);
  stats.losses = num(g, /Total lost\s*(\d+)/i);
  stats.draws = num(g, /Total drawn\s*(\d+)/i);
  stats.game_time = str(g, /Total time spent playing\s*([^\n]+)/i);
  if (stats.game_time === '-' || stats.game_time === '—') stats.game_time = null;

  // ----- Quiz (best-effort; refine labels after first run) -----
  var q = await tabText(page, uuid, 'quiz');
  var quizzes = q.match(/Total quizzes\s*(?:completed\s*)?(\d+)\s*\/\s*(\d+)/i);
  if (quizzes) { stats.quizzes_completed = Number(quizzes[1]); stats.quizzes_total = Number(quizzes[2]); }
  var probs = q.match(/Total problems\s*(?:solved\s*)?(\d+)\s*\/\s*(\d+)/i);
  if (probs) { stats.problems_solved = Number(probs[1]); stats.problems_total = Number(probs[2]); }
  stats.quiz_points = num(q, /Total (?:quiz )?points\s*([\d,]+)/i);
  stats.quiz_time_taken = str(q, /Total time (?:taken|spent)[^\n]*?\s([^\n]+)/i);

  // ----- Tournament -----
  var t = await tabText(page, uuid, 'tournament');
  stats.tournaments_played = num(t, /Total games\s*(\d+)/i);
  stats.tournament_best = str(t, /Best (?:result|finish)\s*([^\n]+)/i);

  return compact(stats);
}

async function main() {
  requireEnv();
  var dry = !!DRY_RUN && DRY_RUN !== '0' && DRY_RUN !== 'false';

  // Trim + sanity-check the secrets (a common mistake is pasting the
  // wrong text into a secret, which otherwise crashes deep in supabase-js).
  var sbUrl = String(SUPABASE_URL || '').trim();
  var sbKey = String(SUPABASE_SERVICE_ROLE_KEY || '').trim();
  if (!/^https:\/\/[^\s]+\.supabase\.co\/?$/.test(sbUrl)) {
    console.error('SUPABASE_URL looks wrong. Expected https://<project>.supabase.co — got something else. Re-check the secret.');
    process.exit(1);
  }
  if (sbKey.split('.').length !== 3 || /[^\x00-\x7f]/.test(sbKey)) {
    console.error('SUPABASE_SERVICE_ROLE_KEY does not look like a Supabase key (a long JWT in 3 dot-separated parts). It looks like the wrong value was pasted into the secret — copy the key from Supabase → Settings → API → "service_role".');
    process.exit(1);
  }
  var supabase = createClient(sbUrl, sbKey, { auth: { persistSession: false } });
  var res = await supabase.from('children').select('id,name,chesslang_id').not('chesslang_id', 'is', null);
  if (res.error) throw res.error;
  var kids = res.data || [];
  if (!kids.length) { console.log('No children have a chesslang_id set — nothing to sync.'); return; }
  console.log('Syncing ' + kids.length + ' linked child(ren)' + (dry ? ' [DRY RUN]' : '') + '…');

  var browser = await chromium.launch();
  var ctx = await browser.newContext({ viewport: { width: 1280, height: 1400 } });
  var page = await ctx.newPage();

  try {
    await login(page);
    console.log('Logged in to ChessLang.');

    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i];
      try {
        var stats = await scrapeStudent(page, kid.chesslang_id);
        console.log('• ' + kid.name + ': ' + JSON.stringify(stats));
        if (dry) continue;
        if (!Object.keys(stats).length) { console.warn('  (no values parsed — skipping upsert)'); continue; }
        var row = Object.assign({ child_id: kid.id, updated_at: new Date().toISOString() }, stats);
        var up = await supabase.from('student_stats').upsert(row, { onConflict: 'child_id' });
        if (up.error) console.error('  upsert failed: ' + up.error.message);
        else console.log('  ✓ updated');
      } catch (e) {
        console.error('  failed for ' + kid.name + ': ' + (e && e.message || e));
        await shot(page, 'kid-' + (kid.chesslang_id || i));
      }
    }
  } finally {
    await browser.close();
  }
  console.log('Done.');
}

main().catch(function (e) { console.error(e); process.exit(1); });
