#!/usr/bin/env node
/**
 * apply-chrome.mjs — splices the federation chrome (exported by
 * @oimlsmart/site-shell's scripts/export-chrome.mjs into
 * vendor/site-shell/dist-chrome/) into the concept-browser's built
 * pages (TODO.fix/07). The concept-browser is a full-document
 * generator with no layout hook, so the shell's header, footer,
 * stylesheet, and island runtime are injected into every emitted HTML
 * file; the shell's hashed assets are merged into dist/_astro/ and
 * their URLs rewritten to this site's base path.
 *
 * Usage: node scripts/apply-chrome.mjs [distDir] [base]
 *   distDir default dist, base default /vocab (no trailing slash).
 */
import { readFileSync, writeFileSync, readdirSync, statSync, mkdirSync, cpSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const DIST = process.argv[2] ?? join(ROOT, 'dist')
const BASE = process.argv[3] ?? '/vocab'
const CHROME = join(ROOT, 'vendor/site-shell/dist-chrome')

for (const f of ['header.html', 'footer.html', 'head.html']) {
  if (!existsSync(join(CHROME, f))) {
    console.error(`${CHROME}/${f} missing — run the shell's chrome export first:`)
    console.error('  (cd vendor/site-shell/test/fixture && npm run build) && node vendor/site-shell/scripts/export-chrome.mjs')
    process.exit(1)
  }
}

// Rewrite the fragments' asset URLs to this site's base. The fixture
// emits root-relative /_astro/... URLs; the site serves them at
// <base>/_astro/ after the merge below.
const rewrite = (text) => text.replaceAll('"/_astro/', `"/${BASE.replace(/^\//, '')}/_astro/`)
const header = rewrite(readFileSync(join(CHROME, 'header.html'), 'utf8')).trim()
const footer = rewrite(readFileSync(join(CHROME, 'footer.html'), 'utf8')).trim()

// The shell's stylesheet needs a two-position injection to compose with
// the site's own Tailwind build. Both files declare the same cascade
// layers, and ties inside a layer break by document order. The correct
// composition is: shell plain rules, then the site build (its plain AND
// responsive rules), then the shell's responsive variants — so each
// side's responsive utilities beat both sides' plain duplicates (the
// sidebar's lg:static AND the chrome's md:hidden both win). We split
// the shell css's @layer utilities into plain vs @media chunks.
function splitChromeCss(css) {
  const layerStart = css.indexOf('@layer utilities{')
  if (layerStart < 0) throw new Error('@layer utilities not found in the shell css')
  const openBrace = layerStart + '@layer utilities'.length
  let depth = 0, i = openBrace
  const chunks = []
  let chunkStart = openBrace + 1
  for (; i < css.length; i++) {
    if (css[i] === '{') depth++
    else if (css[i] === '}') {
      depth--
      if (depth === 0) break
      if (depth === 1) {
        chunks.push(css.slice(chunkStart, i + 1))
        chunkStart = i + 1
      }
    }
  }
  const plain = chunks.filter(c => !c.trimStart().startsWith('@media')).join('')
  const media = chunks.filter(c => c.trimStart().startsWith('@media')).join('')
  const mainCss = css.slice(0, openBrace + 1) + plain + css.slice(i)
  const mediaCss = `@layer utilities{${media}}\n`
  return { mainCss, mediaCss }
}

const shellCssFile = readdirSync(join(CHROME, '_astro')).find(f => /^app\..*\.css$/.test(f))
if (!shellCssFile) throw new Error('the shell app css not found in dist-chrome/_astro')
const { mainCss, mediaCss } = splitChromeCss(readFileSync(join(CHROME, '_astro', shellCssFile), 'utf8'))

const headTags = rewrite(readFileSync(join(CHROME, 'head.html'), 'utf8')).trim()

// Merge the shell's hashed assets into the site's own _astro dir (the
// split css is written over the shell's app css + a media companion).
mkdirSync(join(DIST, '_astro'), { recursive: true })
cpSync(join(CHROME, '_astro'), join(DIST, '_astro'), { recursive: true })
writeFileSync(join(DIST, '_astro', shellCssFile), mainCss)
const mediaFile = shellCssFile.replace(/^app\./, 'app-media.')
writeFileSync(join(DIST, '_astro', mediaFile), mediaCss)
const mediaTag = `<link rel="stylesheet" href="/${BASE.replace(/^\//, '')}/_astro/${mediaFile}">`

function* walk(dir) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) yield* walk(full)
    else if (entry.endsWith('.html')) yield full
  }
}

let injected = 0
for (const file of walk(DIST)) {
  let html = readFileSync(file, 'utf8')
  if (html.includes('class="site-nav')) continue // already chromed

  if (!html.includes('</head>') || !html.includes('<body') || !html.includes('</body>')) {
    console.warn(`skipping ${file}: no head/body markers`)
    continue
  }
  // The shell's stylesheet goes FIRST in head: both this app and the
  // shell ship Tailwind utilities, and ties break by file order. The
  // app's own utilities (incl. its responsive overrides like lg:static)
  // must come last so they win; the shell's classes are either
  // identical declarations or unique to the chrome, so first position
  // is safe for them. The charset meta stays before everything (the
  // 1024-byte sniffing window).
  const charset = html.match(/<meta[^>]*charset[^>]*>/i)
  if (charset) {
    html = html.replace(charset[0], `${charset[0]}\n${headTags}`)
  } else {
    html = html.replace(/<head([^>]*)>/, `<head$1>\n${headTags}`)
  }
  // The shell's responsive-variant companion goes LAST (see the split
  // note above): its media rules must follow the site's own build.
  html = html.replace('</head>', `${mediaTag}\n</head>`)
  // Insert the header right after the body open tag (attributes intact).
  html = html.replace(/<body([^>]*)>/, `<body$1>\n${header}`)
  html = html.replace('</body>', `${footer}\n</body>`)
  writeFileSync(file, html)
  injected++
}
console.log(`chrome applied to ${injected} pages under ${DIST} (base ${BASE})`)
