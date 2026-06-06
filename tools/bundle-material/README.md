# Multi-page material bundler

Turns a folder of interlinked HTML pages into **one self-contained
`.html`** with built-in page navigation, so it can be uploaded as a
single **private** material (links keep working, nothing in the repo).

## Easiest: do it from the Admin page (recommended)
You don't need this script. In **Admin → Topics → Manage → "bundle a
multi-page set into ONE private file"**, multi-select all the `.html`
pages → **Add material**. It bundles them in the browser and uploads the
single file privately. Works from your phone.

## Command-line (optional)
```bash
node tools/bundle-material/bundle.js <folder> [output.html] [indexFile]
# e.g.
node tools/bundle-material/bundle.js materials/basics basics-bundle.html basics-index.html
```
Then upload the output file via the normal **Upload** option.

## Notes
- Internal links (`href="page2.html"`) become in-file navigation — no network request.
- Images/CSS referenced by **relative** paths won't resolve once private;
  use absolute `https://` URLs or inline them. Inline `<style>` is preserved.
- Best for self-contained lesson pages (the kind of templated pages you build).
