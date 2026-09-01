import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFile as execFileCallback } from 'node:child_process'
import { promisify } from 'node:util'
import type { FrontmatterValue, MemoryDoc, VaultSnapshot } from './model.js'

export const DEFAULT_CONTAINER = 'iCloud.aivoiceeeon'
export const DEFAULT_ENVIRONMENT = 'production'
export const DEFAULT_DATABASE = 'private'
export const DEFAULT_ZONE = 'com.apple.coredata.cloudkit.zone'
export const DEFAULT_TEAM_ID = 'BYRK5RUS4U'
const DEFAULT_TOKEN_FILE = path.join(os.homedir(), '.config', 'eeon-mcp', 'cloudkit.json')
const execFile = promisify(execFileCallback)

const NOTE_FIELDS = [
  'CD_id',
  'CD_title',
  'CD_content',
  'CD_transcript',
  'CD_createdAt',
  'CD_updatedAt',
  'CD_aiInsight',
  'CD_calendarContextJSON',
  'CD_column',
  'CD_emotionalTone',
  'CD_enhancedNoteText',
  'CD_inferredProjectName',
  'CD_intentConfidence',
  'CD_intentType',
  'CD_isArchived',
  'CD_isFavorite',
  'CD_mentionedPeopleJSON',
  'CD_personaExtractionsJSON',
  'CD_projectId',
  'CD_sourceTypeRaw',
  'CD_speakerLabelsJSON',
  'CD_summaryFormat',
  'CD_topicsJSON',
  'CD_transcriptionStatus'
]

const NOTE_PROBE_FIELDS = ['CD_id', 'CD_title', 'CD_createdAt', 'CD_updatedAt']

const ARTICLE_FIELDS = [
  'CD_id',
  'CD_name',
  'CD_articleTypeRaw',
  'CD_createdAt',
  'CD_updatedAt',
  'CD_lastCompiledAt',
  'CD_mentionCount',
  'CD_lastMentionedAt',
  'CD_summary',
  'CD_openThreadsJSON',
  'CD_timelineJSON',
  'CD_connectionsJSON',
  'CD_sentimentArc',
  'CD_decisionsJSON',
  'CD_relationshipContext',
  'CD_thinkingEvolution',
  'CD_linkedNoteIdsJSON',
  'CD_aliasesJSON'
]

export type CloudKitEnvironment = 'development' | 'production'
export type CloudKitDatabase = 'private' | 'public' | 'shared'

export type CloudKitConfig = {
  container: string
  environment: CloudKitEnvironment
  database: CloudKitDatabase
  zoneName: string
  teamId?: string
  apiToken?: string
  webAuthToken?: string
  userToken?: string
  tokenFile: string
  baseURL: string
  fetchImpl: typeof fetch
  cktoolRunner?: CktoolRunner
}

export type CloudKitProbe = {
  source: string
  container: string
  environment: CloudKitEnvironment
  database: CloudKitDatabase
  zoneName: string
  mode: 'web' | 'cktool'
  hasApiToken: boolean
  hasExplicitUserToken: boolean
  canReadPrivateDatabase: boolean
  sampleCount: number
  sample?: {
    recordName?: string
    id?: string
    title?: string
    created?: string
    updated?: string
  }
  error?: string
}

type CloudKitRecord = {
  recordName?: string
  recordType?: string
  deleted?: boolean
  fields?: Record<string, { value?: unknown; type?: string }>
  created?: { timestamp?: unknown }
  modified?: { timestamp?: unknown }
}

type CloudKitQueryResponse = {
  records?: CloudKitRecord[]
  continuationMarker?: string
  continuationToken?: string
  ckWebAuthToken?: string
  webAuthToken?: string
  serverErrorCode?: string
  reason?: string
  redirectURL?: string
}

type CktoolRunner = (args: string[]) => Promise<string>

type CloudKitRecordPage = {
  records: CloudKitRecord[]
  continuationToken?: string
}

type StoredToken = {
  container?: string
  environment?: CloudKitEnvironment
  database?: CloudKitDatabase
  webAuthToken?: string
  updatedAt?: string
}

export function cloudKitSourceRequested(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.EEON_SOURCE === 'cloudkit'
    || env.EEON_SOURCE === 'cktool'
    || Boolean(env.EEON_CLOUDKIT_API_TOKEN)
    || Boolean(env.EEON_CLOUDKIT_WEB_AUTH_TOKEN)
    || Boolean(env.CLOUDKIT_USER_TOKEN)
}

export function cloudKitConfigFromEnv(env: NodeJS.ProcessEnv = process.env): CloudKitConfig {
  const tokenFile = env.EEON_CLOUDKIT_TOKEN_FILE || DEFAULT_TOKEN_FILE
  const stored = readTokenFile(tokenFile)
  const userToken = env.EEON_CLOUDKIT_WEB_AUTH_TOKEN || env.CLOUDKIT_USER_TOKEN || stored.webAuthToken
  return {
    container: env.EEON_CLOUDKIT_CONTAINER || stored.container || DEFAULT_CONTAINER,
    environment: parseEnvironment(env.EEON_CLOUDKIT_ENVIRONMENT || stored.environment || DEFAULT_ENVIRONMENT),
    database: parseDatabase(env.EEON_CLOUDKIT_DATABASE || stored.database || DEFAULT_DATABASE),
    zoneName: env.EEON_CLOUDKIT_ZONE || DEFAULT_ZONE,
    teamId: env.EEON_CLOUDKIT_TEAM_ID || DEFAULT_TEAM_ID,
    apiToken: env.EEON_CLOUDKIT_API_TOKEN || env.CLOUDKIT_API_TOKEN,
    webAuthToken: userToken,
    userToken,
    tokenFile,
    baseURL: env.EEON_CLOUDKIT_BASE_URL || 'https://api.apple-cloudkit.com',
    fetchImpl: fetch
  }
}

export async function loadCloudKitSnapshot(config: CloudKitConfig = cloudKitConfigFromEnv()): Promise<VaultSnapshot> {
  const source = sourceLabel(config)
  if (config.apiToken && !config.webAuthToken) {
    return emptyCloudKitSnapshot(
      source,
      [
        'CloudKit Web Services selected, but no private-database user token is saved.',
        'Run eeon-cloudkit-auth, or set EEON_CLOUDKIT_WEB_AUTH_TOKEN/CLOUDKIT_USER_TOKEN.',
        'A cktool management token is not enough to read private notes.'
      ].join(' ')
    )
  }

  try {
    const noteRecords = await fetchAllNotes(config)
    const notes = noteRecords.map(recordToMemoryDoc).filter((doc): doc is MemoryDoc => doc !== null)
    let articles: MemoryDoc[] = []
    try {
      const articleRecords = await fetchAllArticles(config)
      articles = articleRecords.map(recordToArticleDoc).filter((doc): doc is MemoryDoc => doc !== null)
    } catch {
      // Article reads are additive. A schema/token issue here should not hide notes.
    }
    const docs = [...notes, ...articles]
    const lastChange = docs
      .map((doc) => doc.updated ?? doc.date)
      .filter((date): date is string => Boolean(date))
      .sort()
      .at(-1)

    return {
      vault: source,
      source: 'cloudkit',
      docs,
      notes,
      articles,
      legacyNotes: 0,
      icloudPlaceholders: 0,
      lastChange
    }
  } catch (error) {
    return emptyCloudKitSnapshot(source, error instanceof Error ? error.message : String(error))
  }
}

export async function probeCloudKitAccess(config: CloudKitConfig = cloudKitConfigFromEnv()): Promise<CloudKitProbe> {
  const base: Omit<CloudKitProbe, 'canReadPrivateDatabase' | 'sampleCount'> = {
    source: sourceLabel(config),
    container: config.container,
    environment: config.environment,
    database: config.database,
    zoneName: config.zoneName,
    mode: config.apiToken ? 'web' : 'cktool',
    hasApiToken: Boolean(config.apiToken),
    hasExplicitUserToken: Boolean(config.userToken)
  }

  if (config.apiToken && !config.webAuthToken) {
    return {
      ...base,
      canReadPrivateDatabase: false,
      sampleCount: 0,
      error: [
        'CloudKit Web Services selected, but no private-database user token is saved.',
        'Run eeon-cloudkit-auth, or set EEON_CLOUDKIT_WEB_AUTH_TOKEN/CLOUDKIT_USER_TOKEN.',
        'A cktool management token is not enough to read private notes.'
      ].join(' ')
    }
  }

  try {
    const page = await fetchNotePage(config, NOTE_PROBE_FIELDS, 1)
    const first = page.records[0]
    return {
      ...base,
      canReadPrivateDatabase: true,
      sampleCount: page.records.length,
      sample: first ? {
        recordName: first.recordName,
        id: stringField(first, 'CD_id'),
        title: stringField(first, 'CD_title'),
        created: dateField(first, 'CD_createdAt') ?? timestampField(first.created?.timestamp),
        updated: dateField(first, 'CD_updatedAt') ?? timestampField(first.modified?.timestamp)
      } : undefined
    }
  } catch (error) {
    return {
      ...base,
      canReadPrivateDatabase: false,
      sampleCount: 0,
      error: error instanceof Error ? error.message : String(error)
    }
  }
}

export async function fetchCloudKitSignInURL(config: CloudKitConfig): Promise<string> {
  if (!config.apiToken) {
    throw new Error('Missing EEON_CLOUDKIT_API_TOKEN.')
  }
  const url = cloudKitURL(config, 'users/current', false)
  const raw = await config.fetchImpl(url)
  const text = await raw.text()
  const response = text ? JSON.parse(text) as CloudKitQueryResponse : {}
  if (response.redirectURL) return response.redirectURL
  throw new Error('CloudKit did not return a sign-in redirect URL. Check the API token and environment.')
}

export function writeCloudKitTokenFile(config: CloudKitConfig, webAuthToken: string): void {
  const tokenFile = expandHome(config.tokenFile)
  fs.mkdirSync(path.dirname(tokenFile), { recursive: true })
  const payload: StoredToken = {
    container: config.container,
    environment: config.environment,
    database: config.database,
    webAuthToken,
    updatedAt: new Date().toISOString()
  }
  fs.writeFileSync(tokenFile, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 })
  try {
    fs.chmodSync(tokenFile, 0o600)
  } catch {
    // Best effort: Windows and some network filesystems may not support chmod.
  }
}

function readTokenFile(tokenFile: string): StoredToken {
  try {
    return JSON.parse(fs.readFileSync(expandHome(tokenFile), 'utf8')) as StoredToken
  } catch {
    return {}
  }
}

async function fetchAllNotes(config: CloudKitConfig): Promise<CloudKitRecord[]> {
  return fetchAllRecords(config, 'CD_Note', NOTE_FIELDS, 200, 'CD_createdAt')
}

async function fetchAllArticles(config: CloudKitConfig): Promise<CloudKitRecord[]> {
  return fetchAllRecords(config, 'CD_KnowledgeArticle', ARTICLE_FIELDS, 200, 'CD_updatedAt')
}

async function fetchAllRecords(
  config: CloudKitConfig,
  recordType: string,
  fields: string[],
  limit: number,
  sortField: string
): Promise<CloudKitRecord[]> {
  const records: CloudKitRecord[] = []
  let continuationToken: string | undefined
  do {
    const page = await fetchRecordPage(config, recordType, fields, limit, sortField, continuationToken)
    records.push(...page.records)
    continuationToken = page.continuationToken
  } while (continuationToken)
  return records
}

async function fetchNotePage(
  config: CloudKitConfig,
  requestedFields: string[],
  limit: number,
  continuationToken?: string
): Promise<CloudKitRecordPage> {
  return fetchRecordPage(config, 'CD_Note', requestedFields, limit, 'CD_createdAt', continuationToken)
}

async function fetchRecordPage(
  config: CloudKitConfig,
  recordType: string,
  requestedFields: string[],
  limit: number,
  sortField: string,
  continuationToken?: string
): Promise<CloudKitRecordPage> {
  return config.apiToken
    ? fetchRecordPageWithWeb(config, recordType, requestedFields, limit, sortField, continuationToken)
    : fetchRecordPageWithCktool(config, recordType, requestedFields, limit, continuationToken)
}

async function fetchRecordPageWithWeb(
  config: CloudKitConfig,
  recordType: string,
  requestedFields: string[],
  limit: number,
  sortField: string,
  continuationToken?: string
): Promise<CloudKitRecordPage> {
  const body: Record<string, unknown> = {
    zoneID: { zoneName: config.zoneName },
    query: {
      recordType,
      sortBy: [{ fieldName: sortField, ascending: false }]
    },
    desiredKeys: requestedFields,
    resultsLimit: limit,
    numbersAsStrings: false
  }
  if (continuationToken) body.continuationMarker = continuationToken
  const response = await cloudKitRequest(config, 'records/query', body)
  return {
    records: response.records ?? [],
    continuationToken: response.continuationMarker
  }
}

async function fetchRecordPageWithCktool(
  config: CloudKitConfig,
  recordType: string,
  requestedFields: string[],
  limit: number,
  continuationToken?: string
): Promise<CloudKitRecordPage> {
  const args = [
    'query-records',
    '--team-id',
    config.teamId ?? DEFAULT_TEAM_ID,
    '--container-id',
    config.container,
    '--environment',
    config.environment,
    '--database-type',
    config.database,
    '--zone-name',
    config.zoneName,
    '--record-type',
    recordType,
    '--filters',
    'CD_id != __eeon_mcp_never__',
    '--limit',
    String(limit)
  ]
  if (requestedFields.length) {
    args.push('--requested-fields', ...requestedFields)
  }
  if (config.userToken) {
    args.push('--token', config.userToken)
  }
  if (continuationToken) {
    args.push('--continuation-token', continuationToken)
  }

  const response = JSON.parse(await runCktool(config, args)) as CloudKitQueryResponse
  return {
    records: response.records ?? [],
    continuationToken: response.continuationToken ?? response.continuationMarker
  }
}

async function runCktool(config: CloudKitConfig, args: string[]): Promise<string> {
  if (config.cktoolRunner) return config.cktoolRunner(args)
  try {
    const result = await execFile('xcrun', ['cktool', ...args], { maxBuffer: 32 * 1024 * 1024 })
    return result.stdout
  } catch (error) {
    const message = commandErrorMessage(error)
    if (message.includes('No user token found')) {
      throw new Error(
        [
          'CloudKit user-token access is not set up for cktool.',
          'Save a user token with `xcrun cktool save-token --type user`, or set CLOUDKIT_USER_TOKEN.',
          'The existing management token can manage CloudKit schema but cannot read your private notes.'
        ].join(' ')
      )
    }
    throw new Error(`cktool CloudKit query failed: ${message}`)
  }
}

function commandErrorMessage(error: unknown): string {
  if (error && typeof error === 'object') {
    const candidate = error as { message?: unknown; stdout?: unknown; stderr?: unknown }
    const stderr = bufferLikeToString(candidate.stderr)
    const stdout = bufferLikeToString(candidate.stdout)
    const message = typeof candidate.message === 'string' ? candidate.message : ''
    return [stderr, stdout, message].filter(Boolean).join(' ').trim()
  }
  return String(error)
}

function bufferLikeToString(value: unknown): string {
  if (typeof value === 'string') return value.trim()
  if (Buffer.isBuffer(value)) return value.toString('utf8').trim()
  return ''
}

async function cloudKitRequest(
  config: CloudKitConfig,
  endpoint: string,
  body?: unknown,
  options: { includeWebAuthToken?: boolean } = {}
): Promise<CloudKitQueryResponse> {
  const includeWebAuthToken = options.includeWebAuthToken ?? true
  const url = cloudKitURL(config, endpoint, includeWebAuthToken)
  const response = await config.fetchImpl(url, {
    method: body === undefined ? 'GET' : 'POST',
    headers: body === undefined ? undefined : { 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body)
  })
  const text = await response.text()
  const json = text ? JSON.parse(text) as CloudKitQueryResponse : {}
  const rotated = json.ckWebAuthToken ?? json.webAuthToken
  if (rotated && rotated !== config.webAuthToken) {
    config.webAuthToken = rotated
    writeCloudKitTokenFile(config, rotated)
  }
  if (!response.ok || json.serverErrorCode) {
    const reason = json.reason ? `: ${json.reason}` : ''
    const redirect = json.redirectURL ? ` Sign in with eeon-cloudkit-auth.` : ''
    throw new Error(`CloudKit ${json.serverErrorCode ?? response.status}${reason}.${redirect}`)
  }
  return json
}

function cloudKitURL(config: CloudKitConfig, endpoint: string, includeWebAuthToken: boolean): string {
  const url = new URL(
    `/database/1/${config.container}/${config.environment}/${config.database}/${endpoint}`,
    config.baseURL
  )
  url.searchParams.set('ckAPIToken', config.apiToken ?? '')
  if (includeWebAuthToken && config.webAuthToken) {
    url.searchParams.set('ckWebAuthToken', config.webAuthToken)
  }
  return url.toString()
}

function recordToMemoryDoc(record: CloudKitRecord): MemoryDoc | null {
  if (record.deleted) return null
  if (record.recordType && record.recordType !== 'CD_Note') return null
  if (truthyInt(field(record, 'CD_isArchived'))) return null

  const id = stringField(record, 'CD_id') ?? record.recordName
  if (!id) return null
  const title = stringField(record, 'CD_title')
    ?? firstLine(stringField(record, 'CD_content'))
    ?? firstLine(stringField(record, 'CD_transcript'))
    ?? 'Untitled Note'
  const created = dateField(record, 'CD_createdAt') ?? timestampField(record.created?.timestamp)
  const updated = dateField(record, 'CD_updatedAt') ?? timestampField(record.modified?.timestamp)
  const people = jsonStringArray(stringField(record, 'CD_mentionedPeopleJSON'))
  const topics = jsonStringArray(stringField(record, 'CD_topicsJSON'))
  const body = noteBody(record)
  const frontmatter: Record<string, FrontmatterValue> = {
    eeon: 1,
    id,
    kind: 'note',
    title,
    source: stringField(record, 'CD_sourceTypeRaw') ?? 'voice'
  }
  if (created) frontmatter.created = created
  if (updated) frontmatter.updated = updated
  const project = stringField(record, 'CD_inferredProjectName') ?? stringField(record, 'CD_projectId')
  if (project) frontmatter.project = project
  if (people.length) frontmatter.people = people
  if (topics.length) frontmatter.topics = topics
  const tone = stringField(record, 'CD_emotionalTone')
  if (tone) frontmatter.tone = tone
  const format = stringField(record, 'CD_summaryFormat')
  if (format) frontmatter.format = format
  const calendar = calendarContext(stringField(record, 'CD_calendarContextJSON'))
  if (calendar?.title) frontmatter.calendar_event = calendar.title
  if (calendar?.attendees?.length) frontmatter.attendees = calendar.attendees
  const speakers = speakerLabels(stringField(record, 'CD_speakerLabelsJSON'))
  if (speakers.length) frontmatter.speakers = speakers

  return {
    id,
    kind: 'note',
    title,
    file: `cloudkit/${id}.md`,
    date: created,
    updated,
    project,
    people,
    topics,
    aliases: [],
    body,
    frontmatter,
    legacy: false,
    contents: markdownFromDoc(frontmatter, title, created, body, stringField(record, 'CD_transcript'))
  }
}

function recordToArticleDoc(record: CloudKitRecord): MemoryDoc | null {
  if (record.deleted) return null
  if (record.recordType && record.recordType !== 'CD_KnowledgeArticle') return null

  const id = stringField(record, 'CD_id') ?? record.recordName
  const name = stringField(record, 'CD_name')
  if (!id || !name) return null

  const articleType = stringField(record, 'CD_articleTypeRaw') ?? 'topic'
  const created = dateField(record, 'CD_createdAt') ?? timestampField(record.created?.timestamp)
  const updated = dateField(record, 'CD_lastCompiledAt')
    ?? dateField(record, 'CD_updatedAt')
    ?? timestampField(record.modified?.timestamp)
  const aliases = jsonStringArray(stringField(record, 'CD_aliasesJSON'))
  const linkedNotes = jsonStringArray(stringField(record, 'CD_linkedNoteIdsJSON'))
  const openThreads = openThreadItems(record)
  const timeline = timelineItems(record)
  const connections = connectionItems(record)
  const decisions = articleDecisionItems(record)
  const body = articleBody(record, openThreads, timeline, connections, decisions)
  const frontmatter: Record<string, FrontmatterValue> = {
    eeon: 1,
    id,
    kind: 'article',
    article_type: articleType,
    name,
    mentions: numberField(record, 'CD_mentionCount') ?? 0
  }
  if (updated) frontmatter.updated = updated
  const lastMentioned = dateField(record, 'CD_lastMentionedAt')
  if (lastMentioned) frontmatter.last_mentioned = lastMentioned
  if (aliases.length) frontmatter.aliases = aliases
  if (linkedNotes.length) frontmatter.linked_notes = linkedNotes
  if (openThreads.length) frontmatter.open_threads = openThreads
  if (timeline.length) frontmatter.timeline = timeline
  if (connections.length) frontmatter.connections = connections
  if (decisions.length) frontmatter.decisions = decisions

  return {
    id,
    kind: 'article',
    title: name,
    name,
    file: `cloudkit/articles/${articleType}-${slug(name)}-${id.slice(0, 4).toLowerCase()}.md`,
    date: created,
    updated,
    articleType,
    project: articleType === 'project' ? name : undefined,
    people: articleType === 'person' ? [name] : [],
    topics: articleType === 'topic' || articleType === 'reference' ? [name] : [],
    aliases,
    body,
    frontmatter,
    legacy: false,
    contents: markdownFromArticleDoc(frontmatter, name, body)
  }
}

function noteBody(record: CloudKitRecord): string {
  const enhanced = stringField(record, 'CD_enhancedNoteText')
  if (enhanced) return enhanced
  return stringField(record, 'CD_content') ?? stringField(record, 'CD_transcript') ?? ''
}

function markdownFromDoc(
  frontmatter: Record<string, FrontmatterValue>,
  title: string,
  created: string | undefined,
  body: string,
  transcript: string | undefined
): string {
  const lines = ['---', ...Object.entries(frontmatter).map(([key, value]) => yamlLine(key, value)), '---', '', `# ${title}`]
  if (created) lines.push('', `_${created} - EEON_`)
  if (body) lines.push('', body)
  if (transcript && transcript !== body) {
    lines.push('', '---', '', '**Original transcript**', '', transcript)
  }
  return `${lines.join('\n')}\n`
}

function markdownFromArticleDoc(
  frontmatter: Record<string, FrontmatterValue>,
  name: string,
  body: string
): string {
  const lines = ['---', ...Object.entries(frontmatter).map(([key, value]) => yamlLine(key, value)), '---', '', `# ${name}`]
  if (body) lines.push('', body)
  return `${lines.join('\n')}\n`
}

function yamlLine(key: string, value: FrontmatterValue): string {
  if (Array.isArray(value)) {
    if (value.every((item) => typeof item === 'string')) {
      return `${key}: [${value.map((item) => quoteYaml(item)).join(', ')}]`
    }
    const lines = [`${key}:`]
    for (const item of value) {
      lines.push('  -')
      for (const [childKey, childValue] of Object.entries(item)) {
        lines.push(`    ${childKey}: ${quoteYaml(childValue)}`)
      }
    }
    return lines.join('\n')
  }
  if (typeof value === 'string') return `${key}: ${quoteYaml(value)}`
  return `${key}: ${value}`
}

function quoteYaml(value: string): string {
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n')}"`
}

function field(record: CloudKitRecord, name: string): unknown {
  return record.fields?.[name]?.value
}

function numberField(record: CloudKitRecord, name: string): number | undefined {
  const value = field(record, name)
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string') {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) return parsed
  }
  return undefined
}

function stringField(record: CloudKitRecord, name: string): string | undefined {
  const value = field(record, name)
  return typeof value === 'string' && value.trim() ? value : undefined
}

function dateField(record: CloudKitRecord, name: string): string | undefined {
  return timestampField(field(record, name))
}

function timestampField(value: unknown): string | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) return new Date(value).toISOString()
  if (typeof value === 'string') {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) return new Date(parsed).toISOString()
    if (!Number.isNaN(Date.parse(value))) return new Date(value).toISOString()
  }
  return undefined
}

function truthyInt(value: unknown): boolean {
  return value === true || value === 1 || value === '1' || value === 'true'
}

function jsonStringArray(value: string | undefined): string[] {
  if (!value) return []
  try {
    const parsed = JSON.parse(value)
    return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === 'string') : []
  } catch {
    return []
  }
}

function jsonObjectArray(value: string | undefined): Array<Record<string, unknown>> {
  if (!value) return []
  try {
    const parsed = JSON.parse(value)
    return Array.isArray(parsed)
      ? parsed.filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === 'object' && !Array.isArray(item))
      : []
  } catch {
    return []
  }
}

function openThreadItems(record: CloudKitRecord): Record<string, string>[] {
  return jsonObjectArray(stringField(record, 'CD_openThreadsJSON')).flatMap((item) => {
    const thread = stringValue(item.thread)
    if (!thread) return []
    return [{
      thread,
      status: stringValue(item.status) ?? 'open',
      days_open: stringValue(item.daysOpen) ?? stringValue(item.days_open) ?? ''
    }].map(compactRecord)
  })
}

function timelineItems(record: CloudKitRecord): Record<string, string>[] {
  return jsonObjectArray(stringField(record, 'CD_timelineJSON')).flatMap((item) => {
    const event = stringValue(item.event)
    if (!event) return []
    return [compactRecord({
      date: stringValue(item.date) ?? '',
      event
    })]
  })
}

function connectionItems(record: CloudKitRecord): Record<string, string>[] {
  return jsonObjectArray(stringField(record, 'CD_connectionsJSON')).flatMap((item) => {
    const article = stringValue(item.articleName) ?? stringValue(item.article)
    if (!article) return []
    return [compactRecord({
      article,
      reason: stringValue(item.reason) ?? ''
    })]
  })
}

function articleDecisionItems(record: CloudKitRecord): Record<string, string>[] {
  return jsonObjectArray(stringField(record, 'CD_decisionsJSON')).flatMap((item) => {
    const decision = stringValue(item.decision)
    if (!decision) return []
    return [compactRecord({
      decision,
      status: stringValue(item.status) ?? '',
      date: stringValue(item.date) ?? ''
    })]
  })
}

function articleBody(
  record: CloudKitRecord,
  openThreads: Record<string, string>[],
  timeline: Record<string, string>[],
  connections: Record<string, string>[],
  decisions: Record<string, string>[]
): string {
  const parts: string[] = []
  const summary = stringField(record, 'CD_summary')
  if (summary) parts.push(summary)
  const relationship = stringField(record, 'CD_relationshipContext')
  if (relationship) parts.push(`## Relationship Context\n\n${relationship}`)
  const evolution = stringField(record, 'CD_thinkingEvolution')
  if (evolution) parts.push(`## Thinking Evolution\n\n${evolution}`)
  const sentiment = stringField(record, 'CD_sentimentArc')
  if (sentiment) parts.push(`## Sentiment Arc\n\n${sentiment}`)
  if (openThreads.length) {
    parts.push(`## Open Threads\n\n${openThreads.map((item) => `- [${item.status ?? 'open'}] ${item.thread}${item.days_open ? ` (${item.days_open}d)` : ''}`).join('\n')}`)
  }
  if (timeline.length) {
    parts.push(`## Timeline\n\n${timeline.map((item) => `- ${item.date ? `${item.date}: ` : ''}${item.event}`).join('\n')}`)
  }
  if (connections.length) {
    parts.push(`## Connections\n\n${connections.map((item) => `- ${item.article}: ${item.reason ?? ''}`.trim()).join('\n')}`)
  }
  if (decisions.length) {
    parts.push(`## Decisions\n\n${decisions.map((item) => `- [${item.status ?? ''}] ${item.decision}${item.date ? ` (${item.date})` : ''}`).join('\n')}`)
  }
  return parts.join('\n\n')
}

function stringValue(value: unknown): string | undefined {
  if (typeof value === 'string' && value.trim()) return value
  if (typeof value === 'number' && Number.isFinite(value)) return String(value)
  if (typeof value === 'boolean') return String(value)
  return undefined
}

function compactRecord(record: Record<string, string>): Record<string, string> {
  return Object.fromEntries(Object.entries(record).filter(([, value]) => value !== ''))
}

function slug(value: string): string {
  const normalized = value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
  return normalized || 'article'
}

function calendarContext(value: string | undefined): { title?: string; attendees?: string[] } | undefined {
  if (!value) return undefined
  try {
    const parsed = JSON.parse(value) as { title?: unknown; attendees?: unknown }
    return {
      title: typeof parsed.title === 'string' ? parsed.title : undefined,
      attendees: Array.isArray(parsed.attendees)
        ? parsed.attendees.filter((item): item is string => typeof item === 'string')
        : undefined
    }
  } catch {
    return undefined
  }
}

function speakerLabels(value: string | undefined): Record<string, string>[] {
  if (!value) return []
  try {
    const parsed = JSON.parse(value) as Array<Record<string, unknown>>
    if (!Array.isArray(parsed)) return []
    return parsed.flatMap((item) => {
      const marker = typeof item.marker === 'string' ? item.marker : undefined
      const name = typeof item.name === 'string' ? item.name : typeof item.displayName === 'string' ? item.displayName : undefined
      return marker && name ? [{ marker, name }] : []
    })
  } catch {
    return []
  }
}

function firstLine(value: string | undefined): string | undefined {
  return value?.split(/\r?\n/).map((line) => line.trim()).find(Boolean)?.slice(0, 80)
}

function emptyCloudKitSnapshot(vault: string, error: string): VaultSnapshot {
  return {
    vault,
    source: 'cloudkit',
    docs: [],
    notes: [],
    articles: [],
    legacyNotes: 0,
    icloudPlaceholders: 0,
    error
  }
}

function sourceLabel(config: CloudKitConfig): string {
  const mode = config.apiToken ? 'web' : 'cktool'
  return `cloudkit+${mode}://${config.environment}/${config.database}/${config.zoneName}`
}

function parseEnvironment(value: string): CloudKitEnvironment {
  return value.toLowerCase() === 'development' ? 'development' : 'production'
}

function parseDatabase(value: string): CloudKitDatabase {
  const normalized = value.toLowerCase()
  return normalized === 'public' || normalized === 'shared' ? normalized : 'private'
}

function expandHome(value: string): string {
  if (value === '~') return os.homedir()
  if (value.startsWith(`~${path.sep}`)) return path.join(os.homedir(), value.slice(2))
  return value
}
