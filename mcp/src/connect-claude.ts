#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { buildDoctorReport } from './doctor.js'
import { installClaudeMcp } from './install-claude.js'

console.log('EEON Claude CloudKit setup')
console.log('')
console.log('1. Pointing Claude at the CloudKit-backed EEON MCP server...')
const installResult = installClaudeMcp({ apply: true })
console.log(`   Updated ${installResult.configPath}`)
if (installResult.backupPath) console.log(`   Backup: ${installResult.backupPath}`)
console.log('')

console.log('2. Opening Apple CloudKit Console for a private user token.')
console.log('   Generate a User Token, then paste it into this Terminal prompt.')
console.log('   Do not paste CloudKit tokens into chat.')
console.log('')
const saveToken = spawnSync('xcrun', ['cktool', 'save-token', '--type', 'user', '--force'], {
  stdio: 'inherit'
})
if (saveToken.status !== 0) {
  console.error('')
  console.error('CloudKit user-token setup did not complete.')
  process.exit(saveToken.status ?? 1)
}
console.log('')

console.log('3. Verifying that private EEON notes are readable through CloudKit...')
const report = await buildDoctorReport()
console.log(JSON.stringify(report, null, 2))
process.exit(report.verdict === 'ready' ? 0 : 1)
