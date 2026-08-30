#!/usr/bin/env node
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { DEFAULT_ENVIRONMENT, type CloudKitEnvironment } from './cloudkit.js'
import { defaultClaudeConfigPath, defaultProjectRoot } from './doctor.js'

type ClaudeMcpEntry = {
  type: 'stdio'
  command: string
  args: string[]
  env: Record<string, string>
}

export type InstallClaudeOptions = {
  configPath?: string
  projectPath?: string
  repoRoot?: string
  environment?: CloudKitEnvironment
  apply?: boolean
}

export type InstallClaudeResult = {
  applied: boolean
  configPath: string
  projectPath: string
  backupPath?: string
  entry: {
    type: 'stdio'
    command: string
    args: string[]
    envKeys: string[]
  }
}

export function buildClaudeCloudKitEntry(options: {
  repoRoot?: string
  environment?: CloudKitEnvironment
  existingEnv?: Record<string, unknown>
} = {}): ClaudeMcpEntry {
  const repoRoot = options.repoRoot ?? defaultProjectRoot()
  const existingEnv = options.existingEnv ?? {}
  const env: Record<string, string> = {}
  for (const [key, value] of Object.entries(existingEnv)) {
    if (typeof value === 'string' && key !== 'EEON_VAULT') env[key] = value
  }
  env.EEON_SOURCE = 'cloudkit'
  env.EEON_CLOUDKIT_ENVIRONMENT = options.environment ?? DEFAULT_ENVIRONMENT

  return {
    type: 'stdio',
    command: 'node',
    args: [path.join(repoRoot, 'mcp', 'dist', 'src', 'index.js')],
    env
  }
}

export function installClaudeMcp(options: InstallClaudeOptions = {}): InstallClaudeResult {
  const configPath = expandHome(options.configPath ?? defaultClaudeConfigPath())
  const projectPath = options.projectPath ?? defaultProjectRoot()
  const repoRoot = options.repoRoot ?? projectPath
  const parsed = readJsonObject(configPath)
  const existingEntry = existingEeonEntry(parsed, projectPath)
  const entry = buildClaudeCloudKitEntry({
    repoRoot,
    environment: options.environment,
    existingEnv: existingEntry?.env
  })

  ensureProjectMcpServers(parsed, projectPath).eeon = entry

  let backupPath: string | undefined
  if (options.apply) {
    fs.mkdirSync(path.dirname(configPath), { recursive: true })
    if (fs.existsSync(configPath)) {
      backupPath = `${configPath}.bak-${new Date().toISOString().replace(/[:.]/g, '-')}`
      fs.copyFileSync(configPath, backupPath)
    }
    fs.writeFileSync(configPath, `${JSON.stringify(parsed, null, 2)}\n`)
  }

  return {
    applied: Boolean(options.apply),
    configPath,
    projectPath,
    backupPath,
    entry: {
      type: entry.type,
      command: entry.command,
      args: entry.args,
      envKeys: Object.keys(entry.env).sort()
    }
  }
}

function readJsonObject(configPath: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(fs.readFileSync(configPath, 'utf8'))
    return isRecord(parsed) ? parsed : {}
  } catch {
    return {}
  }
}

function ensureProjectMcpServers(config: Record<string, unknown>, projectPath: string): Record<string, unknown> {
  if (!isRecord(config.projects)) config.projects = {}
  const projects = config.projects as Record<string, unknown>
  if (!isRecord(projects[projectPath])) projects[projectPath] = {}
  const project = projects[projectPath] as Record<string, unknown>
  if (!isRecord(project.mcpServers)) project.mcpServers = {}
  return project.mcpServers as Record<string, unknown>
}

function existingEeonEntry(config: Record<string, unknown>, projectPath: string): { env?: Record<string, unknown> } | undefined {
  const projects = isRecord(config.projects) ? config.projects : {}
  const project = isRecord(projects[projectPath]) ? projects[projectPath] : {}
  const projectServers = isRecord(project.mcpServers) ? project.mcpServers : {}
  const projectEntry = projectServers.eeon
  if (isRecord(projectEntry)) return { env: isRecord(projectEntry.env) ? projectEntry.env : undefined }
  const globalServers = isRecord(config.mcpServers) ? config.mcpServers : {}
  const globalEntry = globalServers.eeon
  if (isRecord(globalEntry)) return { env: isRecord(globalEntry.env) ? globalEntry.env : undefined }
  return undefined
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

function environmentArg(): CloudKitEnvironment {
  return argValue('--environment') === 'development' ? 'development' : DEFAULT_ENVIRONMENT
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = installClaudeMcp({
    apply: hasArg('--apply'),
    configPath: argValue('--claude-config'),
    projectPath: argValue('--project'),
    environment: environmentArg()
  })
  console.log(JSON.stringify(result, null, 2))
  if (!result.applied) {
    console.log('')
    console.log('Dry run only. Re-run with `--apply` to update Claude.')
  }
}
