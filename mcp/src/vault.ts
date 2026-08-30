import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import type { FrontmatterValue, MemoryDoc, VaultSnapshot } from './model.js'

export function loadVault(vaultPath: string): VaultSnapshot {
  const resolved = resolveVaultPath(vaultPath)
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isDirectory()) {
    return {
      vault: resolved,
      docs: [],
      notes: [],
      articles: [],
      legacyNotes: 0,
      icloudPlaceholders: 0,
      error: `Vault not found at ${resolved}. Pass --vault or set EEON_VAULT.`
    }
  }

  const files = [
    ...listFiles(resolved),
    ...listFiles(path.join(resolved, 'articles'))
  ]
  const icloudPlaceholders = files.filter((file) => file.endsWith('.icloud')).length
  const markdownFiles = files.filter((file) => file.endsWith('.md'))
  const docs = markdownFiles
    .map((file) => parseMarkdownFile(resolved, file))
    .filter((doc): doc is MemoryDoc => doc !== null)
  const notes = docs.filter((doc) => doc.kind === 'note')
  const articles = docs.filter((doc) => doc.kind === 'article')
  const lastChange = markdownFiles
    .map((file) => fs.statSync(file).mtime)
    .sort((a, b) => b.getTime() - a.getTime())[0]

  return {
    vault: resolved,
    docs,
    notes,
    articles,
    legacyNotes: notes.filter((doc) => doc.legacy).length,
    icloudPlaceholders,
    lastChange: lastChange?.toISOString()
  }
}

function resolveVaultPath(vaultPath: string): string {
  const requested = vaultPath ? path.resolve(expandHome(vaultPath)) : ''
  const candidates = vaultCandidates(requested)

  if (requested && !isKnownEeonVaultPath(requested)) {
    return requested
  }

  if (requested && isDirectory(requested) && (hasMarkdownContent(requested) || !isKnownEeonVaultPath(requested))) {
    return requested
  }

  const populated = candidates.find((candidate) => isDirectory(candidate) && hasMarkdownContent(candidate))
  if (populated) return populated

  const existing = candidates.find((candidate) => isDirectory(candidate))
  if (existing) return existing

  return requested || candidates[0] || path.resolve(vaultPath)
}

function vaultCandidates(requested: string): string[] {
  const home = os.homedir()
  const candidates = [
    requested,
    path.join(home, 'Library', 'Mobile Documents', 'iCloud~aivoiceeeon', 'Documents', 'EEON Vault'),
    path.join(home, 'Library', 'Mobile Documents', 'com~apple~CloudDocs', 'EEON Vault'),
    path.join(home, 'Library', 'Mobile Documents', 'com~apple~CloudDocs', 'Desktop', 'EEON')
  ].filter(Boolean)
  return [...new Set(candidates)]
}

function expandHome(value: string): string {
  if (value === '~') return os.homedir()
  if (value.startsWith(`~${path.sep}`)) return path.join(os.homedir(), value.slice(2))
  return value
}

function isKnownEeonVaultPath(value: string): boolean {
  const normalized = path.normalize(value)
  return normalized.endsWith(path.join('Mobile Documents', 'iCloud~aivoiceeeon', 'Documents', 'EEON Vault'))
    || normalized.endsWith(path.join('Mobile Documents', 'com~apple~CloudDocs', 'EEON Vault'))
    || normalized.endsWith(path.join('Mobile Documents', 'com~apple~CloudDocs', 'Desktop', 'EEON'))
}

function isDirectory(dir: string): boolean {
  return fs.existsSync(dir) && fs.statSync(dir).isDirectory()
}

function hasMarkdownContent(dir: string): boolean {
  return [...listFiles(dir), ...listFiles(path.join(dir, 'articles'))]
    .some((file) => file.endsWith('.md'))
}

function listFiles(dir: string): string[] {
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) return []
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) return []
    return [full]
  })
}

function parseMarkdownFile(root: string, file: string): MemoryDoc | null {
  const raw = fs.readFileSync(file, 'utf8')
  const rel = path.relative(root, file)
  const parsed = splitFrontmatter(raw)
  const title = heading(parsed.body) ?? frontmatterString(parsed.data.title) ?? frontmatterString(parsed.data.name) ?? path.basename(file, '.md')
  const kind = parsed.data.kind === 'article' || rel.startsWith(`articles${path.sep}`) ? 'article' : 'note'
  const id = frontmatterString(parsed.data.id) ?? `file:${rel}`

  if (!parsed.hasFrontmatter) {
    return {
      id,
      kind: 'note',
      title,
      file: rel,
      date: fs.statSync(file).mtime.toISOString(),
      people: [],
      topics: [],
      aliases: [],
      body: parsed.body.trim(),
      frontmatter: {},
      legacy: true
    }
  }

  return {
    id,
    kind,
    title,
    name: frontmatterString(parsed.data.name),
    file: rel,
    date: frontmatterString(parsed.data.created) ?? frontmatterString(parsed.data.last_mentioned),
    updated: frontmatterString(parsed.data.updated),
    project: frontmatterString(parsed.data.project),
    articleType: frontmatterString(parsed.data.article_type),
    people: frontmatterStringArray(parsed.data.people).concat(frontmatterStringArray(parsed.data.attendees)),
    topics: frontmatterStringArray(parsed.data.topics),
    aliases: frontmatterStringArray(parsed.data.aliases),
    body: parsed.body.trim(),
    frontmatter: parsed.data,
    legacy: false
  }
}

function splitFrontmatter(raw: string): { hasFrontmatter: boolean; data: Record<string, FrontmatterValue>; body: string } {
  if (!raw.startsWith('---\n')) {
    return { hasFrontmatter: false, data: {}, body: raw }
  }
  const end = raw.indexOf('\n---', 4)
  if (end === -1) {
    return { hasFrontmatter: false, data: {}, body: raw }
  }
  const block = raw.slice(4, end)
  const body = raw.slice(end + 5)
  return { hasFrontmatter: true, data: parseYamlSubset(block), body }
}

function parseYamlSubset(block: string): Record<string, FrontmatterValue> {
  const out: Record<string, FrontmatterValue> = {}
  const lines = block.split(/\r?\n/)
  let i = 0
  while (i < lines.length) {
    const line = lines[i]
    const pair = /^([A-Za-z0-9_]+):(?:\s*(.*))?$/.exec(line)
    if (!pair) {
      i += 1
      continue
    }

    const key = pair[1]
    const value = pair[2] ?? ''
    if (value === '' && lines[i + 1]?.startsWith('  -')) {
      const items: Record<string, string>[] = []
      i += 1
      while (i < lines.length && lines[i].startsWith('  -')) {
        const item: Record<string, string> = {}
        i += 1
        while (i < lines.length && lines[i].startsWith('    ')) {
          const child = /^\s{4}([A-Za-z0-9_]+):\s*(.*)$/.exec(lines[i])
          if (child) item[child[1]] = parseScalar(child[2]).toString()
          i += 1
        }
        items.push(item)
      }
      out[key] = items
      continue
    }

    out[key] = parseScalar(value)
    i += 1
  }
  return out
}

function parseScalar(raw: string): FrontmatterValue {
  const value = raw.trim()
  if (value.startsWith('[') && value.endsWith(']')) {
    const inner = value.slice(1, -1).trim()
    if (!inner) return []
    return splitYamlList(inner).map(unquote)
  }
  if (value === 'true') return true
  if (value === 'false') return false
  if (/^-?\d+(\.\d+)?$/.test(value)) return Number(value)
  return unquote(value)
}

function splitYamlList(inner: string): string[] {
  const values: string[] = []
  let current = ''
  let quoted = false
  for (let i = 0; i < inner.length; i += 1) {
    const char = inner[i]
    if (char === '"' && inner[i - 1] !== '\\') quoted = !quoted
    if (char === ',' && !quoted) {
      values.push(current.trim())
      current = ''
    } else {
      current += char
    }
  }
  if (current.trim()) values.push(current.trim())
  return values
}

function unquote(value: string): string {
  if (value.startsWith('"') && value.endsWith('"')) {
    return value
      .slice(1, -1)
      .replace(/\\n/g, '\n')
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, '\\')
  }
  return value
}

function heading(body: string): string | undefined {
  return body.split(/\r?\n/).find((line) => line.startsWith('# '))?.replace(/^#\s+/, '').trim()
}

function frontmatterString(value: FrontmatterValue | undefined): string | undefined {
  return typeof value === 'string' && value.trim() ? value : undefined
}

function frontmatterStringArray(value: FrontmatterValue | undefined): string[] {
  return Array.isArray(value) && value.every((item) => typeof item === 'string') ? value : []
}
