// Real hosted MCP SDK compatibility proof. Disposable mirror only; no private
// customer notes, local agent configuration, model calls, or persisted tokens.
// Run: node test/hosted-client.mjs https://www.eeon.com
import assert from 'node:assert/strict'
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
