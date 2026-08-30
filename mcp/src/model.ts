export type MemoryKind = 'note' | 'article'

export type FrontmatterValue = string | number | boolean | string[] | Record<string, string>[]

export type MemoryDoc = {
  id: string
  kind: MemoryKind
  title: string
  name?: string
  file: string
  contents?: string
  date?: string
  updated?: string
  project?: string
  articleType?: string
  people: string[]
  topics: string[]
  aliases: string[]
  body: string
  frontmatter: Record<string, FrontmatterValue>
  legacy: boolean
}

export type OpenLoop = {
  text?: string
  thread?: string
  what?: string
  due?: string
  owner?: string
  who?: string
  status?: string
  note_id?: string
  note_title?: string
  article?: string
  date?: string
  file: string
}

export type VaultSnapshot = {
  vault: string
  source?: 'icloud-drive' | 'cloudkit'
  docs: MemoryDoc[]
  notes: MemoryDoc[]
  articles: MemoryDoc[]
  legacyNotes: number
  icloudPlaceholders: number
  lastChange?: string
  error?: string
}
