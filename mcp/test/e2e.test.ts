import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js'
import { buildDoctorReport, inspectClaudeMcpConfig } from '../src/doctor.js'
import { installClaudeMcp } from '../src/install-claude.js'
import {
  cloudKitConfigFromEnv,
  cloudKitSourceRequested,
  loadCloudKitSnapshot,
  probeCloudKitAccess,
  type CloudKitConfig
} from '../src/cloudkit.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(__dirname, '..', '..')
const appRoot = path.resolve(repoRoot, '..')
const serverPath = path.join(repoRoot, 'dist', 'src', 'index.js')
const fixtureVault = path.join(repoRoot, 'test', 'fixtures', 'vault')

async function withClient(vault: string, fn: (client: Client) => Promise<void>) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [serverPath, '--vault', vault],
    cwd: repoRoot,
    stderr: 'pipe'
  })
  const client = new Client({ name: 'eeon-mcp-test', version: '0.1.0' })
  await client.connect(transport)
  try {
    await fn(client)
  } finally {
    await client.close()
  }
}

function textContent(result: Awaited<ReturnType<Client['callTool']>>): string {
  const content = (result as { content?: Array<{ type?: string; text?: string }> }).content
  const first = content?.[0]
  assert.equal(first?.type, 'text')
  return first.text ?? ''
}

test('search, retrieval, loops, legacy notes, and status work on fixture vault', async () => {
  await withClient(fixtureVault, async (client) => {
    const tools = await client.listTools()
    assert.ok(tools.tools.some((tool) => tool.name === 'search_memory'))

    const search = JSON.parse(textContent(await client.callTool({
      name: 'search_memory',
      arguments: { query: 'pricing', limit: 3 }
    })))
    assert.equal(search[0].title, 'Pricing page standup')

    const note = textContent(await client.callTool({
      name: 'get_note',
      arguments: { id: '11111111-1111-4111-8111-111111111111' }
    }))
    assert.match(note, /actions:/)
    assert.match(note, /Send Lena the pricing draft/)

    const loops = JSON.parse(textContent(await client.callTool({
      name: 'open_loops',
      arguments: {}
    })))
    assert.equal(loops.actions.length, 1)
    assert.equal(loops.commitments.length, 1)
    assert.equal(loops.threads.length, 1)

    const article = textContent(await client.callTool({
      name: 'get_article',
      arguments: { name: 'Lena Ortiz' }
    }))
    assert.match(article, /Pricing feedback/)

    const status = JSON.parse(textContent(await client.callTool({
      name: 'vault_status',
      arguments: {}
    })))
    assert.equal(status.notes, 2)
    assert.equal(status.articles, 1)
    assert.equal(status.legacy_notes, 1)
    assert.equal(status.icloud_placeholders, 1)
  })
})

test('newly written notes are visible without restarting the server', async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'eeon-vault-'))
  fs.cpSync(fixtureVault, temp, { recursive: true })
  await withClient(temp, async (client) => {
    const before = JSON.parse(textContent(await client.callTool({
      name: 'search_memory',
      arguments: { query: 'launch checklist' }
    })))
    assert.equal(before.length, 0)

    fs.writeFileSync(path.join(temp, '2026-08-26-launch-checklist-3333.md'), `---
eeon: 1
id: 33333333-3333-4333-8333-333333333333
kind: note
created: 2026-08-26T15:00:00Z
updated: 2026-08-26T15:01:00Z
title: "Launch checklist"
source: voice
topics: ["launch"]
---

# Launch checklist

Confirm screenshots, support links, and App Review notes.
`)

    const after = JSON.parse(textContent(await client.callTool({
      name: 'search_memory',
      arguments: { query: 'launch checklist' }
    })))
    assert.equal(after[0].title, 'Launch checklist')
  })
})

test('bad vault returns an error through tools instead of crashing', async () => {
  await withClient('/tmp/eeon-missing-vault', async (client) => {
    const status = JSON.parse(textContent(await client.callTool({
      name: 'vault_status',
      arguments: {}
    })))
    assert.match(status.error, /Vault not found/)
  })
})

test('known placeholder-only CloudDocs vault falls back to populated app iCloud vault', async () => {
  const tempHome = fs.mkdtempSync(path.join(os.tmpdir(), 'eeon-home-'))
  const cloudDocsVault = path.join(tempHome, 'Library', 'Mobile Documents', 'com~apple~CloudDocs', 'EEON Vault')
  const appICloudVault = path.join(tempHome, 'Library', 'Mobile Documents', 'iCloud~aivoiceeeon', 'Documents', 'EEON Vault')
  fs.mkdirSync(cloudDocsVault, { recursive: true })
  fs.mkdirSync(appICloudVault, { recursive: true })
  fs.writeFileSync(path.join(cloudDocsVault, '2026-08-29-note.md.icloud'), '')
  fs.writeFileSync(path.join(appICloudVault, '2026-08-29-real-note-4444.md'), `---
eeon: 1
id: 44444444-4444-4444-8444-444444444444
kind: note
created: 2026-08-29T20:00:00Z
updated: 2026-08-29T20:00:00Z
title: "Real synced note"
---

# Real synced note

This note lives in the app-owned iCloud vault.
`)

  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [serverPath, '--vault', cloudDocsVault],
    cwd: repoRoot,
    stderr: 'pipe',
    env: {
      ...process.env,
      HOME: tempHome
    }
  })
  const client = new Client({ name: 'eeon-mcp-test', version: '0.1.0' })
  await client.connect(transport)
  try {
    const status = JSON.parse(textContent(await client.callTool({
      name: 'vault_status',
      arguments: {}
    })))
    assert.equal(status.vault, appICloudVault)
    assert.equal(status.notes, 1)
  } finally {
    await client.close()
  }
})

test('CloudKit source maps private CD_Note records into memory docs', async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'eeon-cloudkit-'))
  const requests: Array<{ url: string; body: Record<string, unknown> }> = []
  const config: CloudKitConfig = {
    container: 'iCloud.aivoiceeeon',
    environment: 'production',
    database: 'private',
    zoneName: 'com.apple.coredata.cloudkit.zone',
    apiToken: 'api-token',
    webAuthToken: 'web-token',
    tokenFile: path.join(temp, 'cloudkit.json'),
    baseURL: 'https://api.apple-cloudkit.com',
    fetchImpl: async (input, init) => {
      const body = JSON.parse(init?.body?.toString() ?? '{}') as Record<string, unknown>
      requests.push({
        url: input.toString(),
        body
      })
      const query = body.query as { recordType?: string } | undefined
      if (query?.recordType === 'CD_KnowledgeArticle') {
        return new Response(JSON.stringify({
          records: [
            {
              recordName: 'article-1',
              recordType: 'CD_KnowledgeArticle',
              fields: {
                CD_id: { value: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' },
                CD_name: { value: 'Lena Ortiz' },
                CD_articleTypeRaw: { value: 'person' },
                CD_summary: { value: 'Lena owns pricing feedback and launch review.' },
                CD_mentionCount: { value: 4 },
                CD_updatedAt: { value: Date.UTC(2026, 7, 29, 17, 0, 0) },
                CD_aliasesJSON: { value: JSON.stringify(['lena']) },
                CD_openThreadsJSON: { value: JSON.stringify([{ thread: 'Confirm annual pricing', status: 'open', daysOpen: 2 }]) },
                CD_timelineJSON: { value: JSON.stringify([{ date: '2026-08-29', event: 'Reviewed pricing page' }]) }
              }
            }
          ]
        }), { status: 200 })
      }

      return new Response(JSON.stringify({
        ckWebAuthToken: 'rotated-token',
        records: [
          {
            recordName: 'record-1',
            recordType: 'CD_Note',
            fields: {
              CD_id: { value: '11111111-1111-4111-8111-111111111111' },
              CD_title: { value: 'Pricing page standup' },
              CD_content: { value: 'Discussed launch pricing and packaging.' },
              CD_transcript: { value: 'Original transcript text.' },
              CD_createdAt: { value: Date.UTC(2026, 7, 29, 14, 0, 0) },
              CD_updatedAt: { value: Date.UTC(2026, 7, 29, 15, 0, 0) },
              CD_isArchived: { value: 0 },
              CD_mentionedPeopleJSON: { value: JSON.stringify(['Lena Ortiz']) },
              CD_topicsJSON: { value: JSON.stringify(['pricing', 'launch']) },
              CD_sourceTypeRaw: { value: 'voice' }
            }
          },
          {
            recordName: 'archived-record',
            recordType: 'CD_Note',
            fields: {
              CD_id: { value: '22222222-2222-4222-8222-222222222222' },
              CD_title: { value: 'Archived note' },
              CD_createdAt: { value: Date.UTC(2026, 7, 28, 14, 0, 0) },
              CD_isArchived: { value: 1 }
            }
          }
        ]
      }), { status: 200 })
    }
  }

  const snapshot = await loadCloudKitSnapshot(config)
  assert.equal(snapshot.source, 'cloudkit')
  assert.equal(snapshot.notes.length, 1)
  assert.equal(snapshot.articles.length, 1)
  assert.equal(snapshot.docs.length, 2)
  assert.equal(snapshot.notes[0].title, 'Pricing page standup')
  assert.equal(snapshot.articles[0].name, 'Lena Ortiz')
  assert.equal(snapshot.articles[0].articleType, 'person')
  assert.match(snapshot.articles[0].contents ?? '', /Confirm annual pricing/)
  assert.deepEqual(snapshot.notes[0].people, ['Lena Ortiz'])
  assert.deepEqual(snapshot.notes[0].topics, ['pricing', 'launch'])
  assert.match(snapshot.notes[0].contents ?? '', /Original transcript text/)
  assert.equal(requests[0].body.zoneID && (requests[0].body.zoneID as { zoneName?: string }).zoneName, 'com.apple.coredata.cloudkit.zone')
  assert.match(requests[0].url, /records\/query/)
  assert.match(fs.readFileSync(config.tokenFile, 'utf8'), /rotated-token/)
})

test('CloudKit probe checks private access without fetching note bodies', async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'eeon-cloudkit-probe-'))
  let requestedBody: Record<string, unknown> | undefined
  const config: CloudKitConfig = {
    container: 'iCloud.aivoiceeeon',
    environment: 'production',
    database: 'private',
    zoneName: 'com.apple.coredata.cloudkit.zone',
    apiToken: 'api-token',
    webAuthToken: 'web-token',
    tokenFile: path.join(temp, 'cloudkit.json'),
    baseURL: 'https://api.apple-cloudkit.com',
    fetchImpl: async (_input, init) => {
      requestedBody = JSON.parse(init?.body?.toString() ?? '{}') as Record<string, unknown>
      return new Response(JSON.stringify({
        records: [
          {
            recordName: 'record-1',
            recordType: 'CD_Note',
            fields: {
              CD_id: { value: '55555555-5555-4555-8555-555555555555' },
              CD_title: { value: 'Probe visible note' },
              CD_createdAt: { value: Date.UTC(2026, 7, 30, 12, 0, 0) }
            }
          }
        ]
      }), { status: 200 })
    }
  }

  const probe = await probeCloudKitAccess(config)
  assert.equal(probe.canReadPrivateDatabase, true)
  assert.equal(probe.sampleCount, 1)
  assert.equal(probe.sample?.title, 'Probe visible note')
  assert.equal(requestedBody?.resultsLimit, 1)
  assert.deepEqual(requestedBody?.desiredKeys, ['CD_id', 'CD_title', 'CD_createdAt', 'CD_updatedAt'])
})

test('CloudKit source can use cktool when no web API token is configured', async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'eeon-cloudkit-cktool-'))
  const calls: string[][] = []
  const config: CloudKitConfig = {
    container: 'iCloud.aivoiceeeon',
    environment: 'production',
    database: 'private',
    zoneName: 'com.apple.coredata.cloudkit.zone',
    teamId: 'BYRK5RUS4U',
    tokenFile: path.join(temp, 'cloudkit.json'),
    baseURL: 'https://api.apple-cloudkit.com',
    fetchImpl: fetch,
    cktoolRunner: async (args) => {
      calls.push(args)
      const recordType = args[args.indexOf('--record-type') + 1]
      if (recordType === 'CD_KnowledgeArticle') {
        return JSON.stringify({
          records: [
            {
              recordName: 'article-1',
              recordType: 'CD_KnowledgeArticle',
              fields: {
                CD_id: { value: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' },
                CD_name: { value: 'Launch' },
                CD_articleTypeRaw: { value: 'topic' },
                CD_summary: { value: 'Launch planning context.' },
                CD_mentionCount: { value: 3 },
                CD_updatedAt: { value: Date.UTC(2026, 7, 29, 17, 0, 0) }
              }
            }
          ]
        })
      }

      return JSON.stringify({
        records: [
          {
            recordName: 'record-1',
            recordType: 'CD_Note',
            fields: {
              CD_id: { value: '33333333-3333-4333-8333-333333333333' },
              CD_title: { value: 'CloudKit cktool note' },
              CD_createdAt: { value: Date.UTC(2026, 7, 29, 16, 0, 0) },
              CD_content: { value: 'Read through local cktool.' }
            }
          }
        ]
      })
    }
  }

  const snapshot = await loadCloudKitSnapshot(config)
  assert.equal(snapshot.source, 'cloudkit')
  assert.equal(snapshot.vault, 'cloudkit+cktool://production/private/com.apple.coredata.cloudkit.zone')
  assert.equal(snapshot.notes[0].title, 'CloudKit cktool note')
  assert.equal(snapshot.articles[0].name, 'Launch')
  assert.equal(calls[0][0], 'query-records')
  assert.equal(calls[0][calls[0].indexOf('--filters') + 1], 'CD_id != __eeon_mcp_never__')
  assert.equal(calls[1][calls[1].indexOf('--record-type') + 1], 'CD_KnowledgeArticle')
  const requestedFieldsIndex = calls[0].indexOf('--requested-fields')
  assert.notEqual(requestedFieldsIndex, -1)
  assert.equal(calls[0].filter((arg) => arg === '--requested-fields').length, 1)
  assert.ok(calls[0].slice(requestedFieldsIndex + 1).includes('CD_content'))
  assert.ok(calls[0].slice(requestedFieldsIndex + 1).includes('CD_enhancedNoteText'))
  assert.ok(calls[0].includes('--team-id'))
  assert.ok(calls[0].includes('BYRK5RUS4U'))
})

test('CloudKit env detection honors cktool user-token naming', () => {
  const tokenFile = path.join(os.tmpdir(), 'missing-eeon-cloudkit-token.json')
  const env = {
    CLOUDKIT_USER_TOKEN: 'user-token',
    EEON_CLOUDKIT_TOKEN_FILE: tokenFile
  } as NodeJS.ProcessEnv

  assert.equal(cloudKitSourceRequested(env), true)
  const config = cloudKitConfigFromEnv(env)
  assert.equal(config.webAuthToken, 'user-token')
  assert.equal(config.userToken, 'user-token')
})

test('CloudKit source reports missing user token clearly', async () => {
  const config: CloudKitConfig = {
    container: 'iCloud.aivoiceeeon',
    environment: 'production',
    database: 'private',
    zoneName: 'com.apple.coredata.cloudkit.zone',
    apiToken: 'api-token',
    tokenFile: path.join(os.tmpdir(), 'missing-eeon-cloudkit-token.json'),
    baseURL: 'https://api.apple-cloudkit.com',
    fetchImpl: fetch
  }

  const snapshot = await loadCloudKitSnapshot(config)
  assert.equal(snapshot.source, 'cloudkit')
  assert.match(snapshot.error ?? '', /private-database user token is saved/)
  assert.match(snapshot.error ?? '', /management token/)
})

test('doctor flags a stale folder-based Claude MCP config', async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'eeon-claude-config-'))
  const configPath = path.join(temp, '.claude.json')
  fs.writeFileSync(configPath, JSON.stringify({
    projects: {
      [appRoot]: {
        mcpServers: {
          eeon: {
            type: 'stdio',
            command: 'node',
            args: [serverPath, '--vault', '/Users/shawncarpenter/Library/Mobile Documents/com~apple~CloudDocs/EEON Vault'],
            env: {}
          }
        }
      }
    }
  }))

  const inspection = inspectClaudeMcpConfig(configPath, appRoot)
  assert.equal(inspection.source, 'folder')
  assert.match(inspection.issues[0], /old folder-export source/)

  const report = await buildDoctorReport({
    configPath,
    projectPath: appRoot,
    skipManagementToken: true,
    environments: ['production'],
    env: {
      EEON_CLOUDKIT_API_TOKEN: 'api-token'
    } as NodeJS.ProcessEnv
  })
  assert.equal(report.verdict, 'misconfigured')
  assert.ok(report.nextActions.some((action) => action.includes('install:claude')))
  assert.ok(report.nextActions.some((action) => action.includes('eeon-cloudkit-auth')))
})

test('install command rewrites Claude EEON MCP config to CloudKit mode', () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'eeon-install-claude-'))
  const configPath = path.join(temp, '.claude.json')
  fs.writeFileSync(configPath, JSON.stringify({
    projects: {
      [appRoot]: {
        mcpServers: {
          eeon: {
            type: 'stdio',
            command: 'node',
            args: [serverPath, '--vault', '/tmp/old-eeon-vault'],
            env: {
              EEON_VAULT: '/tmp/old-eeon-vault',
              KEEP_ME: 'yes'
            }
          },
          other: {
            type: 'stdio',
            command: 'other',
            args: []
          }
        }
      }
    }
  }))

  const result = installClaudeMcp({
    apply: true,
    configPath,
    projectPath: appRoot,
    repoRoot: appRoot,
    environment: 'production'
  })
  assert.equal(result.applied, true)
  assert.ok(result.backupPath)
  assert.ok(fs.existsSync(result.backupPath ?? ''))
  assert.deepEqual(result.entry.envKeys, ['EEON_CLOUDKIT_ENVIRONMENT', 'EEON_SOURCE', 'KEEP_ME'])

  const written = JSON.parse(fs.readFileSync(configPath, 'utf8')) as {
    projects: Record<string, { mcpServers: Record<string, { command?: string; args: string[]; env: Record<string, string> }> }>
  }
  const entry = written.projects[appRoot].mcpServers.eeon
  assert.deepEqual(entry.args, [serverPath])
  assert.equal(entry.env.EEON_SOURCE, 'cloudkit')
  assert.equal(entry.env.EEON_CLOUDKIT_ENVIRONMENT, 'production')
  assert.equal(entry.env.EEON_VAULT, undefined)
  assert.equal(written.projects[appRoot].mcpServers.other.command, 'other')
})

test('CloudKit expired user token maps to actionable re-auth guidance', async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'eeon-cloudkit-expired-'))
  const config: CloudKitConfig = {
    container: 'iCloud.aivoiceeeon',
    environment: 'production',
    database: 'private',
    zoneName: 'com.apple.coredata.cloudkit.zone',
    teamId: 'BYRK5RUS4U',
    tokenFile: path.join(temp, 'cloudkit.json'),
    baseURL: 'https://api.apple-cloudkit.com',
    fetchImpl: fetch,
    cktoolRunner: async () => {
      throw new Error('Session has expired or is invalid. A new user token may be required.')
    }
  }

  const snapshot = await loadCloudKitSnapshot(config)
  assert.ok(snapshot.error, 'expected an error on the snapshot')
  assert.match(snapshot.error ?? '', /missing or expired/i)
  assert.match(snapshot.error ?? '', /save-token --type user/i)
  // The raw cktool dump must NOT be what the user sees.
  assert.doesNotMatch(snapshot.error ?? '', /cktool CloudKit query failed/i)
})
