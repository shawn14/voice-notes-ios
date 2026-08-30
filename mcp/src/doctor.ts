#!/usr/bin/env node
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFile as execFileCallback } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'
import {
  DEFAULT_CONTAINER,
  DEFAULT_ENVIRONMENT,
  DEFAULT_TEAM_ID,
  DEFAULT_ZONE,
  cloudKitConfigFromEnv,
  probeCloudKitAccess,
  type CloudKitEnvironment,
  type CloudKitProbe
} from './cloudkit.js'

const execFile = promisify(execFileCallback)

type ClaudeMcpSource = 'cloudkit' | 'folder' | 'missing' | 'unknown'

export type ClaudeMcpInspection = {
  configPath: string
  projectPath: string
  configured: boolean
  source: ClaudeMcpSource
  command?: string
  args: string[]
  envKeys: string[]
  vaultPath?: string
  issues: string[]
}

export type ManagementTokenCheck = {
  status: 'present' | 'missing' | 'unknown'
  teamIds: string[]
  error?: string
}

export type DoctorReport = {
  observedAt: string
  verdict: 'ready' | 'blocked' | 'misconfigured'
  cloudKit: {
    container: string
    teamId: string
    zoneName: string
    probes: CloudKitProbe[]
    managementToken: ManagementTokenCheck
  }
  localMcp: {
    packageBuilt: boolean
    serverPath: string
    claude: ClaudeMcpInspection
  }
  nextActions: string[]
}

type DoctorOptions = {
  env?: NodeJS.ProcessEnv
  configPath?: string
  projectPath?: string
  environments?: CloudKitEnvironment[]
  skipManagementToken?: boolean
  xcrunRunner?: (args: string[]) => Promise<string>
}

type ClaudeMcpEntry = {
  command?: unknown
  args?: unknown
  env?: unknown
}

export async function buildDoctorReport(options: DoctorOptions = {}): Promise<DoctorReport> {
  const env = options.env ?? process.env
  const projectPath = options.projectPath ?? defaultProjectRoot()
  const configPath = options.configPath ?? defaultClaudeConfigPath()
  const serverPath = path.join(projectPath, 'mcp', 'dist', 'src', 'index.js')
  const environments = options.environments ?? [DEFAULT_ENVIRONMENT as CloudKitEnvironment, 'development']
  const probes: CloudKitProbe[] = []
  for (const environment of environments) {
    probes.push(await probeCloudKitAccess(cloudKitConfigFromEnv({
      ...env,
      EEON_CLOUDKIT_ENVIRONMENT: environment
    })))
  }

  const claude = inspectClaudeMcpConfig(configPath, projectPath)
  const managementToken = options.skipManagementToken
    ? { status: 'unknown' as const, teamIds: [] }
    : await checkManagementToken(options.xcrunRunner)
  const packageBuilt = fs.existsSync(serverPath)
  const nextActions = nextActionsFor({ claude, probes, packageBuilt })
  const verdict = verdictFor({ claude, probes, packageBuilt })

  return {
    observedAt: new Date().toISOString(),
    verdict,
    cloudKit: {
      container: env.EEON_CLOUDKIT_CONTAINER || DEFAULT_CONTAINER,
      teamId: env.EEON_CLOUDKIT_TEAM_ID || DEFAULT_TEAM_ID,
      zoneName: env.EEON_CLOUDKIT_ZONE || DEFAULT_ZONE,
      probes,
      managementToken
    },
    localMcp: {
      packageBuilt,
      serverPath,
      claude
    },
    nextActions
  }
}

export function inspectClaudeMcpConfig(
  configPath: string = defaultClaudeConfigPath(),
  projectPath: string = defaultProjectRoot()
): ClaudeMcpInspection {
  const issues: string[] = []
  const base: ClaudeMcpInspection = {
    configPath,
    projectPath,
    configured: false,
    source: 'missing',
    args: [],
    envKeys: [],
    issues
  }

  let parsed: unknown
  try {
    parsed = JSON.parse(fs.readFileSync(expandHome(configPath), 'utf8'))
  } catch (error) {
    issues.push(`Claude config is not readable at ${configPath}: ${errorMessage(error)}`)
    return base
  }

  const entry = findClaudeEeonEntry(parsed, projectPath)
  if (!entry) {
    issues.push('Claude has no EEON MCP entry for this project.')
    return base
  }

  const args = Array.isArray(entry.args) ? entry.args.filter((arg): arg is string => typeof arg === 'string') : []
  const env = isRecord(entry.env) ? entry.env : {}
  const envKeys = Object.keys(env).sort()
  const vaultPath = vaultPathFromEntry(args, env)
  const source = sourceFromEntry(args, env)
  if (source === 'folder') {
    issues.push('Claude is still configured for the old folder-export source, not CloudKit.')
  }
  if (source === 'unknown') {
    issues.push('Claude has an EEON MCP entry, but it does not declare CloudKit mode or a vault path.')
  }

  return {
    ...base,
    configured: true,
    source,
    command: typeof entry.command === 'string' ? entry.command : undefined,
    args,
    envKeys,
    vaultPath,
    issues
  }
}

export async function checkManagementToken(
  runner: (args: string[]) => Promise<string> = defaultXcrunRunner
): Promise<ManagementTokenCheck> {
  try {
    const output = await runner(['cktool', 'get-teams'])
    return {
      status: 'present',
      teamIds: output
        .split(/\r?\n/)
        .map((line) => line.match(/^\s*([A-Z0-9]{10})\s*:/)?.[1])
        .filter((teamId): teamId is string => Boolean(teamId))
    }
  } catch (error) {
    const message = errorMessage(error)
    const status = /No .*token|not authenticated|Session has expired|expired/i.test(message) ? 'missing' : 'unknown'
    return { status, teamIds: [], error: message }
  }
}

function findClaudeEeonEntry(config: unknown, projectPath: string): ClaudeMcpEntry | undefined {
  if (!isRecord(config)) return undefined
  const projects = isRecord(config.projects) ? config.projects : {}
  const project = isRecord(projects[projectPath]) ? projects[projectPath] : {}
  const projectServers = isRecord(project.mcpServers) ? project.mcpServers : {}
  const projectEntry = projectServers.eeon
  if (isRecord(projectEntry)) return projectEntry

  const globalServers = isRecord(config.mcpServers) ? config.mcpServers : {}
  const globalEntry = globalServers.eeon
  return isRecord(globalEntry) ? globalEntry : undefined
}

function sourceFromEntry(args: string[], env: Record<string, unknown>): ClaudeMcpSource {
  const source = typeof env.EEON_SOURCE === 'string' ? env.EEON_SOURCE.toLowerCase() : ''
  if (source === 'cloudkit' || source === 'cktool') return 'cloudkit'
  if (env.EEON_CLOUDKIT_API_TOKEN || env.EEON_CLOUDKIT_WEB_AUTH_TOKEN || env.CLOUDKIT_USER_TOKEN) return 'cloudkit'
  if (vaultPathFromEntry(args, env)) return 'folder'
  return 'unknown'
}

function vaultPathFromEntry(args: string[], env: Record<string, unknown>): string | undefined {
  const vaultArgIndex = args.indexOf('--vault')
  if (vaultArgIndex >= 0 && typeof args[vaultArgIndex + 1] === 'string') return args[vaultArgIndex + 1]
  return typeof env.EEON_VAULT === 'string' ? env.EEON_VAULT : undefined
}

function verdictFor(input: { claude: ClaudeMcpInspection; probes: CloudKitProbe[]; packageBuilt: boolean }): DoctorReport['verdict'] {
  if (!input.packageBuilt || input.claude.source !== 'cloudkit') return 'misconfigured'
  return input.probes.some((probe) => probe.canReadPrivateDatabase && probe.sampleCount > 0) ? 'ready' : 'blocked'
}

function nextActionsFor(input: { claude: ClaudeMcpInspection; probes: CloudKitProbe[]; packageBuilt: boolean }): string[] {
  const actions: string[] = []
  if (!input.packageBuilt) {
    actions.push('Build the MCP package: `cd mcp && npm run build`.')
  }
  if (input.claude.source !== 'cloudkit') {
    actions.push('Switch Claude from the old folder-export MCP entry to CloudKit: `cd mcp && npm run install:claude -- --apply`.')
  }

  const noUserToken = input.probes.every((probe) =>
    !probe.canReadPrivateDatabase && /user token|private-database user token|No user token|Could not read token from keychain/i.test(probe.error ?? '')
  )
  if (noUserToken) {
    actions.push('Authorize private CloudKit reads for this Apple ID: run `xcrun cktool save-token --type user`, then rerun `cd mcp && npm run doctor`.')
  }

  const keychainBlocked = input.probes.some((probe) =>
    !probe.canReadPrivateDatabase && /Could not read token from keychain/i.test(probe.error ?? '')
  )
  if (keychainBlocked) {
    actions.push('If this doctor is running inside Codex sandbox, rerun it from normal Terminal or allow an escalated `xcrun cktool` check so macOS Keychain can be read.')
  }

  const webAuthMissing = input.probes.some((probe) =>
    probe.mode === 'web' && !probe.canReadPrivateDatabase && /eeon-cloudkit-auth|private-database user token/i.test(probe.error ?? '')
  )
  if (webAuthMissing) {
    actions.push('For CloudKit Web Services, run `eeon-cloudkit-auth` or `cd mcp && npm run auth` with `EEON_CLOUDKIT_API_TOKEN` set.')
  }

  const readableButEmpty = input.probes.some((probe) => probe.canReadPrivateDatabase && probe.sampleCount === 0)
  if (readableButEmpty) {
    actions.push('CloudKit private access works, but no `CD_Note` sample was found; check whether this build wrote notes to Production or Development CloudKit.')
  }

  if (!actions.length) {
    actions.push('Restart the AI client so it reloads the CloudKit-backed EEON MCP entry.')
  }
  return actions
}

function defaultXcrunRunner(args: string[]): Promise<string> {
  return execFile('xcrun', args, { maxBuffer: 1024 * 1024 }).then((result) => result.stdout)
}

export function defaultClaudeConfigPath(): string {
  return path.join(os.homedir(), '.claude.json')
}

export function defaultProjectRoot(): string {
  const here = path.dirname(fileURLToPath(import.meta.url))
  if (path.basename(here) === 'src' && path.basename(path.dirname(here)) === 'dist') {
    return path.resolve(here, '..', '..', '..')
  }
  if (path.basename(here) === 'src') {
    return path.resolve(here, '..', '..')
  }
  return process.cwd()
}

function errorMessage(error: unknown): string {
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}

function expandHome(value: string): string {
  if (value === '~') return os.homedir()
  if (value.startsWith(`~${path.sep}`)) return path.join(os.homedir(), value.slice(2))
  return value
}

function argValue(name: string): string | undefined {
  const index = process.argv.indexOf(name)
  return index >= 0 ? process.argv[index + 1] : undefined
}

function hasArg(name: string): boolean {
  return process.argv.includes(name)
}

function cliEnvironments(): CloudKitEnvironment[] {
  const value = argValue('--environment') ?? process.env.EEON_CLOUDKIT_ENVIRONMENT ?? 'both'
  if (value === 'both') return [DEFAULT_ENVIRONMENT as CloudKitEnvironment, 'development']
  return [value === 'development' ? 'development' : DEFAULT_ENVIRONMENT as CloudKitEnvironment]
}

function printHuman(report: DoctorReport): void {
  console.log('EEON CloudKit Doctor')
  console.log(`Verdict: ${report.verdict}`)
  console.log(`MCP server: ${report.localMcp.packageBuilt ? 'built' : 'not built'} (${report.localMcp.serverPath})`)
  console.log(`Claude EEON source: ${report.localMcp.claude.source}`)
  if (report.localMcp.claude.vaultPath) console.log(`Old vault path: ${report.localMcp.claude.vaultPath}`)
  for (const issue of report.localMcp.claude.issues) console.log(`Issue: ${issue}`)
  console.log(`CloudKit management token: ${report.cloudKit.managementToken.status}`)
  for (const probe of report.cloudKit.probes) {
    const status = probe.canReadPrivateDatabase ? 'readable' : 'blocked'
    const sample = probe.sampleCount > 0 ? `, sample: ${probe.sample?.title ?? probe.sample?.id ?? probe.sample?.recordName ?? 'present'}` : ''
    console.log(`CloudKit ${probe.environment}/${probe.mode}: ${status}, sample_count=${probe.sampleCount}${sample}`)
    if (probe.error) console.log(`CloudKit ${probe.environment} error: ${probe.error}`)
  }
  console.log('Next:')
  for (const action of report.nextActions) console.log(`- ${action}`)
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const report = await buildDoctorReport({
    configPath: argValue('--claude-config'),
    projectPath: argValue('--project'),
    environments: cliEnvironments(),
    skipManagementToken: hasArg('--skip-management-token')
  })
  if (hasArg('--json')) {
    console.log(JSON.stringify(report, null, 2))
  } else {
    printHuman(report)
  }
  process.exit(report.verdict === 'ready' ? 0 : 1)
}
