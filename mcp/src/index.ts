#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { z } from 'zod'
import { loadMemorySnapshot } from './source.js'
import { EeonTools, textResult } from './tools.js'

function argValue(name: string): string | undefined {
  const index = process.argv.indexOf(name)
  return index >= 0 ? process.argv[index + 1] : undefined
}

const vaultPath = argValue('--vault') ?? process.env.EEON_VAULT ?? ''

const server = new McpServer(
  { name: 'eeon-mcp', version: '0.1.0' },
  {
    instructions: 'Read-only access to EEON memory. Use search_memory first, then get_note/get_article for full context.'
  }
)

const tools = new EeonTools(() => loadMemorySnapshot(vaultPath))

server.registerTool(
  'search_memory',
  {
    title: 'Search EEON memory',
    description: 'Search notes and compiled knowledge articles in the exported EEON vault.',
    inputSchema: {
      query: z.string(),
      limit: z.number().int().min(1).max(50).optional(),
      kind: z.enum(['note', 'article', 'any']).optional(),
      since: z.string().optional()
    }
  },
  async (args) => textResult(await tools.searchMemory(args))
)

server.registerTool(
  'get_note',
  {
    title: 'Get EEON note',
    description: 'Return one note markdown document, including frontmatter and transcript.',
    inputSchema: { id: z.string() }
  },
  async (args) => textResult(await tools.getNote(args))
)

server.registerTool(
  'recent_notes',
  {
    title: 'Recent EEON notes',
    description: 'List recent notes from the EEON vault.',
    inputSchema: {
      days: z.number().int().min(1).max(3650).optional(),
      limit: z.number().int().min(1).max(100).optional()
    }
  },
  async (args) => textResult(await tools.recentNotes(args))
)

server.registerTool(
  'list_articles',
  {
    title: 'List EEON knowledge articles',
    description: 'List compiled knowledge articles by type.',
    inputSchema: { article_type: z.enum(['person', 'project', 'topic', 'self', 'purpose', 'reference', 'index']).optional() }
  },
  async (args) => textResult(await tools.listArticles(args))
)

server.registerTool(
  'get_article',
  {
    title: 'Get EEON article',
    description: 'Return a compiled knowledge article by name, alias, or id.',
    inputSchema: { name: z.string() }
  },
  async (args) => textResult(await tools.getArticle(args))
)

server.registerTool(
  'open_loops',
  {
    title: 'Open EEON loops',
    description: 'Return incomplete actions, commitments, and open article threads.',
    inputSchema: {
      person: z.string().optional(),
      project: z.string().optional()
    }
  },
  async (args) => textResult(await tools.openLoops(args))
)

server.registerTool(
  'people',
  {
    title: 'EEON people',
    description: 'List people articles and their open commitments.',
    inputSchema: {}
  },
  async () => textResult(await tools.people())
)

server.registerTool(
  'vault_status',
  {
    title: 'EEON vault status',
    description: 'Report note/article counts, legacy files, iCloud placeholders, and configuration errors.',
    inputSchema: {}
  },
  async () => textResult(await tools.vaultStatus())
)

const transport = new StdioServerTransport()
await server.connect(transport)
