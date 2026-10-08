// Actual native Codex consumes the unchanged packet copied by the iPad UI.
// Offline packet path: no connector, publication or user configuration changes.
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { mkdtemp, readFile, writeFile, mkdir, rm, copyFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { createHash } from 'node:crypto'
const [input, output, priorOutput] = process.argv.slice(2)
assert(input && output, 'Pass actual copied-brief.md and receipt directory')
const brief = await readFile(resolve(input), 'utf8')
assert(brief.includes('Build a landing page for this project'))
const ids = [...brief.matchAll(/Note ID: ([0-9A-F-]{36})/g)].map(match => match[1])
assert.equal(ids.length, 4, 'Native seeded iPad packet has four source IDs')
const workspace = await mkdtemp(join(tmpdir(), 'eeon-copied-brief-'))
try {
  await writeFile(join(workspace, 'brief.md'), brief)
  if (priorOutput) { for (const name of ['index.html','handoff-result.md']) await copyFile(join(resolve(priorOutput),name),join(workspace,name)) }
  const child = spawn('codex', ['exec', '--ignore-user-config', '--ephemeral', '--skip-git-repo-check', '--sandbox', 'workspace-write', '--json', '-'], { cwd: workspace, stdio: ['pipe', 'pipe', 'pipe'] })
  let events = '', diagnostics = ''
  child.stdout.on('data', data => { events += data })
  child.stderr.on('data', data => { diagnostics += data })
  const timer = setTimeout(() => child.kill('SIGTERM'), 180000)
  const completed = new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve) })
  child.stdin.end(`This is a disposable local integration test. The workspace is the correct location for the copied request. Implement a standalone index.html draft prototype with no dependencies, external assets, network calls or publication. Clearly mark the page as a draft; do not invent pricing or completed capabilities. Use plain full-width rows and typography, without content cards; the primary working surface/action should be visible on desktop and phone. Any essential unknown can remain an explicit placeholder in this local draft. Browser feedback: never leave an enabled button that silently does nothing. Capture is not implemented in this local landing draft, so show it as disabled with an adjacent explicit unavailable/draft label. Browse knowledge must be a real anchor to the knowledge section. Use a compact first viewport without a large blank vertical gap, and keep controls above the fixed footer. In the existing draft .hero still has min-height:calc(100vh - 136px) and align-items:end, leaving hundreds of blank pixels above content. Remove the min-height declaration and set align-items:start; do not reintroduce viewport-height hero sizing. The Working Surface heading should be within the first 300px on desktop. If existing draft files are present, repair them using this feedback. Create handoff-result.md recording source note IDs, produced files, what was actually verified and what remains unresolved. Keep reported completion in a note distinct from independently verified work. The exact packet copied from the app follows unchanged:\n\n${brief}`)
  let code
  try { code = await completed } finally { clearTimeout(timer) }
  await mkdir(resolve(output), { recursive: true })
  await writeFile(join(output, 'native-trace.jsonl'), events)
  await writeFile(join(output, 'native-diagnostics.txt'), diagnostics, { mode: 0o600 })
  assert.equal(code, 0, 'Native client must complete')
  const page = await readFile(join(workspace, 'index.html'), 'utf8')
  const report = await readFile(join(workspace, 'handoff-result.md'), 'utf8')
  assert(/draft|prototype/i.test(page), 'Draft state must be visible')
  assert(/viewport/i.test(page), 'Phone viewport must be specified')
  assert(/EEON/.test(page))
  for (const id of ids) assert(report.includes(id), 'Result must cite each source')
  assert(/unresolved|unknown|not verified/i.test(report))
  await writeFile(join(output, 'brief.md'), brief)
  await copyFile(join(workspace, 'index.html'), join(output, 'index.html'))
  await copyFile(join(workspace, 'handoff-result.md'), join(output, 'handoff-result.md'))
  await writeFile(join(output, 'receipt.json'), JSON.stringify({ passed: true, inputSha256: createHash('sha256').update(brief).digest('hex'), sourceIds: ids, scope: 'actual native copied packet to local draft; browser proof pending; no publication or connector access' }, null, 2))
  console.log('PASS native client consumed exact iPad packet and produced source-cited local draft; browser proof pending')
} finally {
  await rm(workspace, { recursive: true, force: true })
}
