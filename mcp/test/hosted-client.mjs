// Real hosted MCP SDK compatibility proof. Disposable mirror only; no private
// customer notes, local agent configuration, model calls, or persisted tokens.
// Run: node test/hosted-client.mjs https://www.eeon.com
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { mkdtemp, readFile, rm, mkdir, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { randomUUID } from 'node:crypto'
import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js'
import { UnauthorizedError } from '@modelcontextprotocol/sdk/client/auth.js'
const base = process.argv[2]
assert(base, 'Pass the actual deployment URL')
const url = new URL('/api/mcp', base)
const ua = { 'User-Agent': 'Mozilla/5.0 eeon-sdk-interop' }
const request = async (path, init = {}) => {
  const response = await fetch(new URL(path, base), { ...init, headers: { ...ua, ...init.headers }, signal: AbortSignal.timeout(30000) })
  assert(response.ok, `HTTP ${response.status} at ${path.split('?')[0]}`)
  return response
}
const json = async (path, init) => (await request(path, init)).json()
const revoke = async token => {
  const response = await fetch(new URL('/api/connect/revoke', base), {
    method: 'POST', redirect: 'manual', headers: { ...ua, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ token }), signal: AbortSignal.timeout(30000)
  })
  assert.equal(response.status, 307, 'Revoke returns its documented redirect')
  assert(new URL(response.headers.get('location'), base).searchParams.has('revoked'))
}
const pass = message => console.log('PASS ' + message)
let primary, client, transport
try {
  primary = (await json('/api/connect/device', { method: 'POST' })).token
  assert(primary)
  const headers = { Authorization: `Bearer ${primary}`, 'Content-Type': 'application/json' }
  const noteId = randomUUID()
  const now = Date.now()
  const up = await json('/api/mirror', { method: 'POST', headers, body: JSON.stringify({ upserts: [{ recordType: 'CD_Note', id: noteId, fields: { CD_id: noteId, CD_title: 'Founder SDK compatibility proof', CD_enhancedNoteText: 'Project Orbit: draft a launch plan. Keep unfinished work distinct from done work.', CD_createdAt: now, CD_updatedAt: now, CD_inferredProjectName: 'Orbit' } }] }) })
  assert.equal(up.notes, 1)
  pass('disposable source uploaded')
  let info, tokens, verifier, authCode
  const provider = {
    redirectUrl: 'http://localhost:53682/callback',
    clientMetadata: { client_name: 'EEON SDK interop proof', redirect_uris: ['http://localhost:53682/callback'], grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'], token_endpoint_auth_method: 'none' },
    clientInformation: () => info,
    saveClientInformation: value => { info = value },
    tokens: () => tokens,
    saveTokens: value => { tokens = value },
    saveCodeVerifier: value => { verifier = value },
    codeVerifier: () => verifier,
    redirectToAuthorization: async authorizationUrl => {
      const page = await (await request(authorizationUrl.toString())).text()
      const code = page.match(/([A-Z2-9]{3})-([A-Z2-9]{3})<\/div>/)
      const session = page.match(/sessionId\\?":\\?"([A-Za-z0-9_-]+)/)
      assert(code && session, 'Real authorization page has approval code/session')
      const paired = await json('/api/pair', { method: 'POST', headers, body: JSON.stringify({ code: code[1] + code[2], approve: true }) })
      assert.equal(paired.status, 'approved')
      const poll = await json('/api/oauth/poll?session=' + session[1])
      assert.equal(poll.status, 'approved')
      const callback = new URL(poll.redirect)
      assert.equal(callback.origin + callback.pathname, provider.redirectUrl)
      assert.equal(callback.searchParams.get('state'), authorizationUrl.searchParams.get('state'))
      authCode = callback.searchParams.get('code')
      pass('SDK discovery + dynamic registration + PKCE reach actual approval')
    }
  }
  const options = { authProvider: provider, fetch: (input, init = {}) => fetch(input, { ...init, headers: new Headers([...new Headers(init.headers), ...Object.entries(ua)]), signal: AbortSignal.timeout(30000) }) }
  transport = new StreamableHTTPClientTransport(url, options)
  client = new Client({ name: 'EEON SDK proof', version: '1.0' })
  await assert.rejects(client.connect(transport), UnauthorizedError)
  assert(authCode)
  await transport.finishAuth(authCode)
  assert(tokens?.access_token)
  // Failed initial transport must be replaced; credentials remain in memory.
  await client.close()
  transport = new StreamableHTTPClientTransport(url, options)
  client = new Client({ name: 'EEON SDK proof', version: '1.0' })
  await client.connect(transport)
  assert.equal(client.getServerVersion()?.name, 'eeon-mcp')
  pass('SDK initializes and accepts server capabilities')
  const { tools } = await client.listTools()
  for (const name of ['search_memory', 'get_note', 'recent_notes', 'list_articles', 'get_article', 'open_loops', 'people', 'vault_status']) assert(tools.some(tool => tool.name === name), name)
  pass('SDK validates discovery of all eight memory tools')
  const search = await client.callTool({ name: 'search_memory', arguments: { query: 'Orbit', kind: 'note' } })
  assert(!search.isError)
  assert(JSON.stringify(search).includes(noteId))
  const note = await client.callTool({ name: 'get_note', arguments: { id: noteId } })
  assert(!note.isError)
  assert(JSON.stringify(note).includes('Keep unfinished work distinct'))
  pass('SDK search and get_note read the real mirrored source')
  if (process.argv.includes('--native-codex') || process.argv.includes('--native-claude')) {
    const isClaude = process.argv.includes('--native-claude')
    const agentName = isClaude ? 'Claude Code' : 'Codex'
    const workspace = await mkdtemp(join(tmpdir(), 'eeon-codex-proof-'))
    try {
      let args = ['exec', '--ignore-user-config', '--ephemeral', '--skip-git-repo-check', '--sandbox', 'workspace-write', '--json',
        '-c', 'mcp_servers.eeon.url=' + JSON.stringify(url.toString()),
        '-c', 'mcp_servers.eeon.bearer_token_env_var="EEON_PROOF_AGENT_TOKEN"',
        '-c', 'mcp_servers.eeon.enabled_tools=["get_note"]',
        '-c', 'mcp_servers.eeon.tools.get_note.approval_mode="approve"', '-']
      if (isClaude) {
        const configPath = join(workspace, 'eeon-mcp.json')
        await writeFile(configPath, JSON.stringify({ mcpServers: { eeon: { type: 'http', url: url.toString(), headers: { Authorization: `Bearer ${tokens.access_token}` } } } }), { mode: 0o600 })
        args = ['--print', '--restricted', '--strict-mcp-config', '--mcp-config', configPath, '--no-session-persistence', '--output-format', 'stream-json', '--verbose', '--tools', 'Write', '--allowedTools', 'mcp__eeon__get_note,Write']
      }
      const child = spawn(isClaude ? 'claude' : 'codex', args, { cwd: workspace, env: { ...process.env, EEON_PROOF_AGENT_TOKEN: tokens.access_token }, stdio: ['pipe', 'pipe', 'pipe'] })
      let events = '', diagnostics = ''
      child.stdout.on('data', data => { events += data })
      child.stderr.on('data', data => { diagnostics += data })
      const timeout = setTimeout(() => child.kill('SIGTERM'), 120000)
      const completed = new Promise((resolve, reject) => { child.on('error', reject); child.on('close', code => resolve(code)) })
      child.stdin.end(`Use the EEON MCP get_note tool to read note ID ${noteId}. Then create launch-plan.md in this workspace from that source. Include the project name, a practical next step, and a section explicitly separating unfinished work from completed work. Do not access other notes, contact anyone, publish, deploy, or run external services. Do not claim anything was completed merely because it appears in the note. This is a disposable integration test. Report the source note ID and output path.`)
      let code
      try { code = await completed } finally { clearTimeout(timeout) }
      assert.equal(code, 0, `Native ${agentName} exits successfully (diagnostics withheld to avoid credential leakage)`)
      const records = events.split('\n').filter(Boolean).map(line => JSON.parse(line))
      const receiptDir = process.argv.find(arg => arg.startsWith('--receipt-dir='))?.slice('--receipt-dir='.length)
      const redact = value => value.replaceAll(tokens.access_token, '[REDACTED]').replaceAll(primary, '[REDACTED]').replaceAll(verifier, '[REDACTED]')
      const trace = isClaude ? records.filter(record => ['assistant', 'user', 'result'].includes(record.type)).map(record => JSON.parse(redact(JSON.stringify(record)))) : records.map(record => ({ type: record.type, item: record.item ? { type: record.item.type, status: record.item.status, server: record.item.server, tool: record.item.tool, arguments: record.item.type === 'mcp_tool_call' ? JSON.parse(redact(JSON.stringify(record.item.arguments ?? {}))) : undefined, result: record.item.type === 'mcp_tool_call' ? JSON.parse(redact(JSON.stringify(record.item.result ?? {}))) : undefined, error: record.item.error, text: record.item.type === 'agent_message' ? redact(record.item.text ?? '') : undefined } : undefined }))
      if (receiptDir) { await mkdir(receiptDir, { recursive: true }); await writeFile(join(receiptDir, 'native-trace.json'), JSON.stringify(trace, null, 2)) }
      if (isClaude) {
        const uses = records.flatMap(record => record.message?.content ?? []).filter(item => item.type === 'tool_use' && item.name === 'mcp__eeon__get_note' && item.input?.id === noteId)
        const results = records.flatMap(record => record.message?.content ?? []).filter(item => item.type === 'tool_result' && !item.is_error && uses.some(use => use.id === item.tool_use_id))
        assert(uses.length && results.some(result => JSON.stringify(result).includes('Orbit')), 'Native Claude trace proves successful source tool call')
      } else assert(records.some(record => record.item?.type === 'mcp_tool_call' && record.item?.tool === 'get_note' && record.item?.status === 'completed'), 'Native client trace proves actual get_note call')
      const plan = await readFile(join(workspace, 'launch-plan.md'), 'utf8')
      if (receiptDir) await writeFile(join(receiptDir, 'launch-plan.md'), redact(plan))
      assert(plan.includes('Orbit') && plan.includes(noteId), 'Produced artifact reflects cited project source')
      assert(/unfinished|incomplete|not.*completed|not.*done/i.test(plan), 'Produced artifact distinguishes unfinished work')
      console.log(`PASS native ${agentName} actual get_note trace + inspected launch-plan.md; authentication seeded from disposable SDK OAuth, native login flow not tested`)
    } finally { await rm(workspace, { recursive: true, force: true }) }
  }
  await revoke(primary)
  primary = null
  const denied = await fetch(url, { method: 'POST', headers: { ...ua, Authorization: `Bearer ${tokens.access_token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 99, method: 'tools/list' }), signal: AbortSignal.timeout(30000) })
  assert.equal(denied.status, 401)
  pass('disconnect revokes SDK credentials')
} finally {
  await client?.close().catch(() => {})
  if (primary) await revoke(primary)
  pass('disposable connection cleanup completed')
}
