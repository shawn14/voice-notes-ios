import fs from 'node:fs'
import path from 'node:path'
import type { MemoryDoc, OpenLoop, VaultSnapshot } from './model.js'
import { searchDocs } from './search.js'

export class EeonTools {
  constructor(private readonly getSnapshot: () => VaultSnapshot | Promise<VaultSnapshot>) {}

  async vaultStatus() {
    const snapshot = await this.getSnapshot()
    return {
      vault: snapshot.vault,
      source: snapshot.source ?? 'icloud-drive',
      notes: snapshot.notes.length,
      legacy_notes: snapshot.legacyNotes,
      articles: snapshot.articles.length,
      last_change: snapshot.lastChange ?? null,
      icloud_placeholders: snapshot.icloudPlaceholders,
      semantic: 'off',
      error: snapshot.error ?? null
    }
  }

  async searchMemory(args: { query: string; limit?: number; kind?: 'note' | 'article' | 'any'; since?: string }) {
    const snapshot = await this.getSnapshot()
    if (snapshot.error) return { error: snapshot.error }
    return searchDocs(snapshot.docs, args.query, {
      limit: args.limit,
      kind: args.kind ?? 'any',
      since: args.since
    })
  }

  async getNote(args: { id: string }) {
    return this.readDoc(args.id, 'note')
  }

  async recentNotes(args: { days?: number; limit?: number }) {
    const snapshot = await this.getSnapshot()
    if (snapshot.error) return { error: snapshot.error }
    const days = args.days ?? 7
    const cutoff = Date.now() - days * 24 * 60 * 60 * 1000
    return snapshot.notes
      .filter((doc) => !doc.date || Date.parse(doc.date) >= cutoff)
      .sort((a, b) => Date.parse(b.date ?? '') - Date.parse(a.date ?? ''))
      .slice(0, Math.max(1, Math.min(args.limit ?? 20, 100)))
      .map((doc) => ({
        id: doc.id,
        title: doc.title,
        date: doc.date,
        project: doc.project,
        people: doc.people,
        topics: doc.topics,
        first_line: doc.body.split(/\r?\n/).find((line) => line.trim() && !line.startsWith('#'))?.trim() ?? ''
      }))
  }

  async listArticles(args: { article_type?: string }) {
    const snapshot = await this.getSnapshot()
    if (snapshot.error) return { error: snapshot.error }
    return snapshot.articles
      .filter((doc) => !args.article_type || doc.articleType === args.article_type)
      .sort((a, b) => Date.parse(b.updated ?? '') - Date.parse(a.updated ?? ''))
      .map((doc) => ({
        id: doc.id,
        name: doc.name ?? doc.title,
        article_type: doc.articleType,
        updated: doc.updated,
        mentions: doc.frontmatter.mentions ?? 0,
        open_thread_count: block(doc, 'open_threads').length,
        file: doc.file
      }))
  }

  async getArticle(args: { name: string }) {
    const snapshot = await this.getSnapshot()
    if (snapshot.error) return { error: snapshot.error }
    const needle = args.name.toLowerCase()
    const doc = snapshot.articles.find((candidate) =>
      candidate.id.toLowerCase() === needle ||
      candidate.title.toLowerCase() === needle ||
      candidate.name?.toLowerCase() === needle ||
      candidate.aliases.some((alias) => alias.toLowerCase() === needle)
    )
    if (!doc) return { error: `Article not found: ${args.name}` }
    return this.fileText(doc)
  }

  async openLoops(args: { person?: string; project?: string }) {
    const snapshot = await this.getSnapshot()
    if (snapshot.error) return { error: snapshot.error }
    const actions: OpenLoop[] = []
    const commitments: OpenLoop[] = []
    const threads: OpenLoop[] = []
    for (const doc of snapshot.docs) {
      if (!matches(doc, args)) continue
      for (const action of block(doc, 'actions')) {
        if (action.done === 'true') continue
        actions.push({
          text: action.text,
          due: action.due,
          owner: action.owner,
          note_id: doc.id,
          note_title: doc.title,
          date: doc.date,
          file: doc.file
        })
      }
      for (const commitment of block(doc, 'commitments')) {
        if (commitment.done === 'true') continue
        commitments.push({
          who: commitment.who,
          what: commitment.what,
          note_id: doc.id,
          note_title: doc.title,
          date: doc.date,
          file: doc.file
        })
      }
      for (const thread of block(doc, 'open_threads')) {
        if (thread.status === 'resolved' || thread.status === 'closed') continue
        threads.push({
          thread: thread.thread,
          status: thread.status,
          article: doc.name ?? doc.title,
          file: doc.file
        })
      }
    }
    return { actions, commitments, threads }
  }

  async people() {
    const snapshot = await this.getSnapshot()
    if (snapshot.error) return { error: snapshot.error }
    return snapshot.articles
      .filter((doc) => doc.articleType === 'person')
      .map((doc) => ({
        name: doc.name ?? doc.title,
        mentions: doc.frontmatter.mentions ?? 0,
        last_mentioned: doc.frontmatter.last_mentioned ?? null,
        open_commitments: openCommitmentCount(snapshot, doc.name ?? doc.title)
      }))
      .sort((a, b) => String(b.last_mentioned ?? '').localeCompare(String(a.last_mentioned ?? '')))
  }

  private async readDoc(id: string, kind: MemoryDoc['kind']) {
    const snapshot = await this.getSnapshot()
    if (snapshot.error) return { error: snapshot.error }
    const needle = id.toLowerCase()
    const doc = snapshot.docs.find((candidate) =>
      candidate.kind === kind &&
      (candidate.id.toLowerCase() === needle || candidate.file.toLowerCase() === needle)
    )
    if (!doc) return { error: `${kind === 'note' ? 'Note' : 'Article'} not found: ${id}` }
    return this.fileText(doc)
  }

  private async fileText(doc: MemoryDoc) {
    if (doc.contents !== undefined) return doc.contents
    const snapshot = await this.getSnapshot()
    const fullPath = path.join(snapshot.vault, doc.file)
    return fs.readFileSync(fullPath, 'utf8')
  }
}

function block(doc: MemoryDoc, key: string): Record<string, string>[] {
  const value = doc.frontmatter[key]
  return Array.isArray(value) && value.every((item) => typeof item === 'object') ? value as Record<string, string>[] : []
}

function matches(doc: MemoryDoc, args: { person?: string; project?: string }): boolean {
  if (args.project && doc.project?.toLowerCase() !== args.project.toLowerCase()) return false
  if (args.person) {
    const needle = args.person.toLowerCase()
    return doc.people.some((person) => person.toLowerCase() === needle) ||
      doc.name?.toLowerCase() === needle ||
      doc.aliases.some((alias) => alias.toLowerCase() === needle)
  }
  return true
}

function openCommitmentCount(snapshot: VaultSnapshot, person: string): number {
  let count = 0
  for (const doc of snapshot.docs) {
    if (!matches(doc, { person })) continue
    for (const commitment of block(doc, 'commitments')) {
      if (commitment.done !== 'true') count += 1
    }
  }
  return count
}

export function textResult(value: unknown) {
  return { content: [{ type: 'text' as const, text: typeof value === 'string' ? value : JSON.stringify(value, null, 2) }] }
}
