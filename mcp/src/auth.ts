#!/usr/bin/env node
import { spawn } from 'node:child_process'
import http from 'node:http'
import { cloudKitConfigFromEnv, fetchCloudKitSignInURL, writeCloudKitTokenFile } from './cloudkit.js'

const DEFAULT_PORT = 43777

function argValue(name: string): string | undefined {
  const index = process.argv.indexOf(name)
  return index >= 0 ? process.argv[index + 1] : undefined
}

function hasArg(name: string): boolean {
  return process.argv.includes(name)
}

const port = Number(argValue('--port') ?? process.env.EEON_CLOUDKIT_CALLBACK_PORT ?? DEFAULT_PORT)
const config = cloudKitConfigFromEnv({
  ...process.env,
  EEON_CLOUDKIT_API_TOKEN: argValue('--api-token') ?? process.env.EEON_CLOUDKIT_API_TOKEN,
  EEON_CLOUDKIT_ENVIRONMENT: argValue('--environment') ?? process.env.EEON_CLOUDKIT_ENVIRONMENT,
  EEON_CLOUDKIT_CONTAINER: argValue('--container') ?? process.env.EEON_CLOUDKIT_CONTAINER,
  EEON_CLOUDKIT_TOKEN_FILE: argValue('--token-file') ?? process.env.EEON_CLOUDKIT_TOKEN_FILE
})

if (!config.apiToken) {
  console.error('Missing EEON_CLOUDKIT_API_TOKEN. Create a CloudKit API token for iCloud.aivoiceeeon, then pass it as --api-token or an environment variable.')
  process.exit(2)
}

const timeout = setTimeout(() => {
  console.error('Timed out waiting for Apple sign-in callback.')
  server.close()
  process.exit(1)
}, 5 * 60 * 1000)

const server = http.createServer((req, res) => {
  const url = new URL(req.url ?? '/', `http://127.0.0.1:${port}`)
  if (url.pathname !== '/callback') {
    res.writeHead(404, { 'content-type': 'text/plain' })
    res.end('Not found')
    return
  }

  const token = url.searchParams.get('ckWebAuthToken')
  if (!token) {
    res.writeHead(400, { 'content-type': 'text/plain' })
    res.end('Apple did not return ckWebAuthToken. Check the CloudKit API token callback URL.')
    return
  }

  writeCloudKitTokenFile(config, token)
  clearTimeout(timeout)
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' })
  res.end(`
<!doctype html>
<html>
<head><meta charset="utf-8"><title>EEON Connected</title></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 40px;">
  <h1>EEON AI access is connected</h1>
  <p>You can close this window and return to your AI tool.</p>
</body>
</html>
`)
  server.close(() => process.exit(0))
})

server.listen(port, '127.0.0.1', async () => {
  try {
    const redirectURL = await fetchCloudKitSignInURL(config)
    console.log(`Listening for Apple sign-in at http://127.0.0.1:${port}/callback`)
    console.log(`Token file: ${config.tokenFile}`)
    console.log('')
    console.log('Open this URL and sign in with the Apple ID that owns your EEON notes:')
    console.log(redirectURL)
    if (!hasArg('--no-open')) {
      spawn('open', [redirectURL], { stdio: 'ignore', detached: true }).unref()
    }
  } catch (error) {
    clearTimeout(timeout)
    server.close()
    console.error(error instanceof Error ? error.message : String(error))
    process.exit(1)
  }
})
