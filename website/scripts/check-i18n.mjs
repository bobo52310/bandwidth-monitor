#!/usr/bin/env node
// i18n guard for the marketing site.
//
//   node scripts/check-i18n.mjs          check the four locale JSON files
//   node scripts/check-i18n.mjs --dist   also scan the built HTML in dist/
//
// Exit code 0 = clean, 1 = at least one problem, 2 = could not run.
//
// Checks
//   (a) every locale has exactly the same flattened key set as zh-Hant
//       (array items are keyed by index, e.g. faq.items[0].answer)
//   (b) no locale value contains a claim the product cannot back up
//   (c) no locale value contains a download call-to-action
//   (d) --dist only: the rendered text of every dist/**/*.html also passes (b) and (c),
//       which catches strings hardcoded in components
//
// "下載" / "ダウンロード" / "다운로드" used as the network speed direction are allowed;
// only download *actions* are rejected by (c).

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const siteRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const localesDir = join(siteRoot, 'src/i18n/locales')
const distDir = join(siteRoot, 'dist')

const REFERENCE = 'zh-Hant'
const LOCALES = [REFERENCE, 'en', 'ja', 'ko']
const SHOW_LIMIT = 12

// (b) claims that are false, unverifiable, or retired wording.
const BANNED_CLAIMS =
  /\bDMG\b|GitHub|App Store|Speedtest|Ookla|エンタープライズ|엔터프라이즈|プロフェッショナル級|전문가급|Network Peak Monitor|ネットワークピークモニター|네트워크 피크 모니터|macOS 13|Ventura|免費|無料|무료|\bfree\b|v1\.0\.0/i

// (c) download actions (the product is not downloadable yet).
const BANNED_DOWNLOAD_ACTIONS =
  /Download for|Download ·|Download now|Grab the|立即下載|下載並安裝|從.*下載|今すぐダウンロード|ダウンロードして|지금 다운로드|다운로드하/i

const RULES = [
  { id: 'b', label: 'banned claim', pattern: BANNED_CLAIMS },
  { id: 'c', label: 'download action', pattern: BANNED_DOWNLOAD_ACTIONS },
]

const args = new Set(process.argv.slice(2))
const unknownArgs = [...args].filter((a) => a !== '--dist')
if (unknownArgs.length > 0) {
  console.error(`Unknown argument: ${unknownArgs.join(' ')}\nUsage: node scripts/check-i18n.mjs [--dist]`)
  process.exit(2)
}
const scanDist = args.has('--dist')

let problems = 0
const fail = (message) => {
  problems += 1
  console.log(message)
}

// ---- load + flatten -------------------------------------------------------

function flatten(node, path, out) {
  if (Array.isArray(node)) {
    if (node.length === 0) out.set(path, '')
    node.forEach((item, i) => flatten(item, `${path}[${i}]`, out))
  } else if (node !== null && typeof node === 'object') {
    for (const [key, value] of Object.entries(node)) {
      flatten(value, path ? `${path}.${key}` : key, out)
    }
  } else {
    out.set(path, node)
  }
  return out
}

const flat = {}
for (const locale of LOCALES) {
  const file = join(localesDir, `${locale}.json`)
  try {
    flat[locale] = flatten(JSON.parse(readFileSync(file, 'utf8')), '', new Map())
  } catch (error) {
    console.error(`Cannot read ${relative(siteRoot, file)}: ${error.message}`)
    process.exit(2)
  }
}

// ---- (a) key sets ---------------------------------------------------------

console.log(`(a) key sets vs ${REFERENCE} (${flat[REFERENCE].size} keys)`)
for (const locale of LOCALES.filter((l) => l !== REFERENCE)) {
  const missing = [...flat[REFERENCE].keys()].filter((k) => !flat[locale].has(k))
  const extra = [...flat[locale].keys()].filter((k) => !flat[REFERENCE].has(k))
  if (missing.length === 0 && extra.length === 0) {
    console.log(`    ${locale}: ok (${flat[locale].size} keys)`)
    continue
  }
  fail(`    ${locale}: ${missing.length} missing, ${extra.length} extra`)
  for (const [label, list] of [['missing', missing], ['extra', extra]]) {
    list.slice(0, SHOW_LIMIT).forEach((k) => console.log(`        ${label}: ${k}`))
    if (list.length > SHOW_LIMIT) console.log(`        ${label}: ... and ${list.length - SHOW_LIMIT} more`)
  }
}

// Non-string leaves would make t() and the (b)/(c) scans meaningless.
for (const locale of LOCALES) {
  for (const [key, value] of flat[locale]) {
    if (typeof value !== 'string') fail(`    ${locale}: ${key} is ${typeof value}, expected string`)
  }
}

// ---- (b)(c) locale values -------------------------------------------------

console.log('(b)(c) forbidden wording in locale values')
let localeHits = 0
for (const locale of LOCALES) {
  for (const [key, value] of flat[locale]) {
    if (typeof value !== 'string') continue
    for (const rule of RULES) {
      const match = value.match(rule.pattern)
      if (!match) continue
      localeHits += 1
      fail(`    ${locale}: ${key} -> ${rule.label} "${match[0]}"`)
    }
  }
}
if (localeHits === 0) console.log('    ok')

// ---- (d) dist -------------------------------------------------------------

const NAMED_ENTITIES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', middot: '·',
  rarr: '→', larr: '←', uarr: '↑', darr: '↓', ndash: '–', mdash: '—', copy: '©', hellip: '…',
}

function decodeEntities(text) {
  return text
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(parseInt(dec, 10)))
    .replace(/&([a-z]+);/gi, (whole, name) => NAMED_ENTITIES[name.toLowerCase()] ?? whole)
}

function listHtml(dir) {
  const found = []
  for (const name of readdirSync(dir)) {
    const full = join(dir, name)
    if (statSync(full).isDirectory()) found.push(...listHtml(full))
    else if (name.endsWith('.html')) found.push(full)
  }
  return found
}

// Visible text nodes plus the attributes users can see or hear:
// <meta content>, aria-label, alt, title.
function extractTexts(html) {
  const texts = []
  const stripped = html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '')

  for (const m of stripped.matchAll(/>([^<]+)</g)) texts.push(m[1])
  for (const m of stripped.matchAll(/<meta\b[^>]*?\bcontent="([^"]*)"/gi)) texts.push(m[1])
  for (const m of stripped.matchAll(/\b(?:aria-label|alt|title)="([^"]*)"/gi)) texts.push(m[1])

  return texts.map((t) => decodeEntities(t).replace(/\s+/g, ' ').trim()).filter(Boolean)
}

if (scanDist) {
  console.log('(d) forbidden wording in rendered dist/**/*.html')
  if (!existsSync(distDir)) {
    fail('    dist/ not found. Run `npm run build` first.')
  } else {
    const files = listHtml(distDir)
    if (files.length === 0) fail('    dist/ contains no .html files.')
    let distHits = 0
    for (const file of files) {
      for (const text of new Set(extractTexts(readFileSync(file, 'utf8')))) {
        for (const rule of RULES) {
          const match = text.match(rule.pattern)
          if (!match) continue
          distHits += 1
          fail(`    ${relative(siteRoot, file)}: ${rule.label} "${match[0]}" in "${text.slice(0, 80)}"`)
        }
      }
    }
    if (distHits === 0 && files.length > 0) console.log(`    ok (${files.length} files)`)
  }
}

console.log(problems === 0 ? '\ncheck-i18n: PASS' : `\ncheck-i18n: FAIL (${problems} problem${problems === 1 ? '' : 's'})`)
process.exit(problems === 0 ? 0 : 1)
