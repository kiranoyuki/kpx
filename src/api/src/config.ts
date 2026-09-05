// Parses and validates process.env once, at import time, so a bad environment
// fails at startup rather than partway through a request.

import { fileURLToPath } from 'node:url'

const NODE_ENVS = ['development', 'test', 'production'] as const
type NodeEnv = (typeof NODE_ENVS)[number]

export interface Config {
  nodeEnv: NodeEnv
  port: number
  host: string
  databasePath: string
}

/**
 * `db/kpx.db` at the repository root, resolved from this module's own location
 * rather than from `process.cwd()` — the API is started from `src/api/` by npm
 * scripts, from the repo root by some editors, and from anywhere at all by a
 * process manager. Source (`src/api/src/`) and build output (`src/api/dist/`)
 * sit at the same depth, so one relative path serves both.
 */
const DEFAULT_DATABASE_PATH = fileURLToPath(new URL('../../../db/kpx.db', import.meta.url))

function parseNodeEnv(raw: string | undefined): NodeEnv {
  const value = raw ?? 'development'
  if (!(NODE_ENVS as readonly string[]).includes(value)) {
    throw new Error(`Invalid NODE_ENV: "${value}" (expected one of ${NODE_ENVS.join(', ')})`)
  }
  return value as NodeEnv
}

function parsePort(raw: string | undefined): number {
  const value = raw ?? '3000'
  const port = Number(value)
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new Error(`Invalid PORT: "${value}" (expected an integer between 1 and 65535)`)
  }
  return port
}

function parseDatabasePath(raw: string | undefined): string {
  if (raw === undefined || raw === '') return DEFAULT_DATABASE_PATH
  return raw
}

function parseConfig(env: NodeJS.ProcessEnv): Config {
  return {
    nodeEnv: parseNodeEnv(env.NODE_ENV),
    port: parsePort(env.PORT),
    host: env.HOST ?? '0.0.0.0',
    databasePath: parseDatabasePath(env.DATABASE_PATH),
  }
}

export const config: Config = parseConfig(process.env)
