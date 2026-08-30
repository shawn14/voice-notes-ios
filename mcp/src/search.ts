import type { MemoryDoc } from './model.js'

export type SearchResult = {
  id: string
  kind: MemoryDoc['kind']
  title: string
  date?: string
  project?: string
  score: number
  snippet: string
  file: string
}

export function searchDocs(
  docs: MemoryDoc[],
  query: string,
  options: { limit?: number; kind?: 'note' | 'article' | 'any'; since?: string } = {}
): SearchResult[] {
  const tokens = tokenize(query)
  const since = options.since ? Date.parse(options.since) : undefined
  const kind = options.kind ?? 'any'
  if (tokens.length === 0) return []

  return docs
    .filter((doc) => kind === 'any' || doc.kind === kind)
    .filter((doc) => !since || !doc.date || Date.parse(doc.date) >= since)
    .map((doc) => ({ doc, score: scoreDoc(doc, tokens) }))
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, clamp(options.limit ?? 10, 1, 50))
    .map(({ doc, score }) => ({
      id: doc.id,
      kind: doc.kind,
      title: doc.title,
      date: doc.date,
      project: doc.project,
      score,
      snippet: snippet(doc, tokens),
      file: doc.file
    }))
}

export function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[^a-z0-9]+/i)
    .map((token) => token.trim())
    .filter((token) => token.length >= 2)
}

function scoreDoc(doc: MemoryDoc, tokens: string[]): number {
  const fields = [
    { text: doc.title, weight: 5 },
    { text: doc.name ?? '', weight: 5 },
    { text: doc.project ?? '', weight: 4 },
    { text: doc.people.join(' '), weight: 3 },
    { text: doc.topics.join(' '), weight: 3 },
    { text: doc.aliases.join(' '), weight: 3 },
    { text: doc.body, weight: 1 }
  ]
  return fields.reduce((sum, field) => {
    const haystack = field.text.toLowerCase()
    return sum + tokens.reduce((tokenSum, token) => {
      const exact = count(haystack, token)
      const prefix = haystack.includes(token.slice(0, Math.max(3, token.length - 1))) ? 0.25 : 0
      return tokenSum + (exact + prefix) * field.weight
    }, 0)
  }, 0)
}

function count(text: string, token: string): number {
  let total = 0
  let index = text.indexOf(token)
  while (index !== -1) {
    total += 1
    index = text.indexOf(token, index + token.length)
  }
  return total
}

function snippet(doc: MemoryDoc, tokens: string[]): string {
  const compact = doc.body.replace(/\s+/g, ' ').trim()
  const lower = compact.toLowerCase()
  const firstHit = tokens
    .map((token) => lower.indexOf(token))
    .filter((index) => index >= 0)
    .sort((a, b) => a - b)[0]
  if (firstHit === undefined) return compact.slice(0, 220)
  const start = Math.max(0, firstHit - 80)
  const end = Math.min(compact.length, firstHit + 180)
  return `${start > 0 ? '...' : ''}${compact.slice(start, end)}${end < compact.length ? '...' : ''}`
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value))
}
