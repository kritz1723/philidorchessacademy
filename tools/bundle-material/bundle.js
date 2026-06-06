#!/usr/bin/env node
/* ============================================================
 * Philidor Chess Academy — multi-page material bundler
 *
 * Combines a folder of interlinked HTML pages into ONE
 * self-contained .html file with built-in page navigation, so it
 * can be uploaded as a single PRIVATE material (Admin -> Topics ->
 * Upload). Page-to-page links keep working *inside* the file, and
 * nothing goes into the public repo.
 *
 * Usage:
 *   node bundle.js <folder> [output.html] [indexFile]
 * Example:
 *   node tools/bundle-material/bundle.js materials/basics basics-bundle.html basics-index.html
 *
 * Notes:
 *  - Internal links like href="basics-castling.html" become in-file
 *    navigation (no network request).
 *  - Images/CSS referenced by RELATIVE paths won't resolve once private;
 *    use absolute https URLs or inline them. Inline <style> is preserved.
 * ============================================================ */
var fs = require('fs');
var path = require('path');

var dir = process.argv[2];
var out = process.argv[3] || 'bundled-material.html';
var indexArg = process.argv[4] || '';

if (!dir || !fs.existsSync(dir)) {
  console.error('Usage: node bundle.js <folder> [output.html] [indexFile]');
  process.exit(1);
}

var files = fs.readdirSync(dir).filter(function (f) { return /\.html?$/i.test(f); });
if (!files.length) { console.error('No .html files in ' + dir); process.exit(1); }

// Put the index page first (so it shows by default).
function isIndex(f) { return indexArg ? f === indexArg : /(^|[-_])index\.html?$/i.test(f); }
files.sort(function (a, b) { return (isIndex(b) ? 1 : 0) - (isIndex(a) ? 1 : 0) || a.localeCompare(b); });

function pick(re, s) { var m = s.match(re); return m ? m[1] : ''; }

var styleSet = [];          // de-duplicated <style> blocks
var sections = [];          // { file, body }
var title = 'Material';

files.forEach(function (f) {
  var html = fs.readFileSync(path.join(dir, f), 'utf8');
  var styles = html.match(/<style[^>]*>[\s\S]*?<\/style>/gi) || [];
  styles.forEach(function (block) {
    var inner = block.replace(/<\/?style[^>]*>/gi, '');
    if (styleSet.indexOf(inner) === -1) styleSet.push(inner);
  });
  var body = pick(/<body[^>]*>([\s\S]*?)<\/body>/i, html) || html;
  sections.push({ file: f, body: body });
  if (isIndex(f)) { title = pick(/<title>([^<]*)<\/title>/i, html) || title; }
});

var headLinks = ''; // keep Google Fonts preconnect/link if present in the index
var idxHtml = fs.readFileSync(path.join(dir, files[0]), 'utf8');
(idxHtml.match(/<link[^>]+fonts[^>]*>/gi) || []).forEach(function (l) { headLinks += '  ' + l + '\n'; });

var sectionHtml = sections.map(function (s) {
  return '<section class="pca-page" data-page="' + s.file + '">\n' + s.body + '\n</section>';
}).join('\n');

var router = [
  '<script>',
  '(function(){',
  '  var pages = [].slice.call(document.querySelectorAll(".pca-page"));',
  '  function show(name){',
  '    var found=false;',
  '    pages.forEach(function(p){ var on = p.getAttribute("data-page")===name; p.style.display = on?"block":"none"; if(on) found=true; });',
  '    if(!found && pages[0]) pages[0].style.display="block";',
  '    window.scrollTo(0,0);',
  '  }',
  '  function fromHash(){ var h=decodeURIComponent((location.hash||"").replace(/^#/,"")).replace(/^.*\\//,""); if(/\\.html?$/i.test(h)) show(h); else if(pages[0]) show(pages[0].getAttribute("data-page")); }',
  '  document.addEventListener("click", function(e){ var a=e.target.closest && e.target.closest(\'a[href$=".html"], a[href$=".htm"]\'); if(!a) return; var href=a.getAttribute("href").replace(/^.*\\//,""); e.preventDefault(); if(location.hash==="#"+href) fromHash(); else location.hash=href; });',
  '  window.addEventListener("hashchange", fromHash);',
  '  fromHash();',
  '})();',
  '</script>'
].join('\n');

var doc = [
  '<!DOCTYPE html>',
  '<html lang="en">',
  '<head>',
  '<meta charset="UTF-8">',
  '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
  '<title>' + title + '</title>',
  headLinks,
  '<style>' + styleSet.join('\n') + '\n.pca-page{display:none}</style>',
  '</head>',
  '<body>',
  sectionHtml,
  router,
  '</body>',
  '</html>'
].join('\n');

fs.writeFileSync(out, doc);
console.log('Bundled ' + sections.length + ' page(s) -> ' + out + ' (' + Math.round(doc.length/1024) + ' KB)');
console.log('Pages:', sections.map(function (s) { return s.file; }).join(', '));
