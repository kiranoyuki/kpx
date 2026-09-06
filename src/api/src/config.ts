// Parses and validates process.env once, at import time, so a bad environment
// fails at startup rather than partway through a request.

import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

/**
 * Loads `src/api/.env` if it is there, using Node's own loader — no dotenv
 * dependency. Without this `.env.example` documents variables that nothing ever
 * reads, and a clean clone cannot start.
 */
const ENV_FILE = fileURLToPath(new URL('../.env', import.meta.url))
if (existsSync(ENV_FILE)) process.loadEnvFile(ENV_FILE)

const NODE_ENVS = ['development', 'test', 'production'] as const
type NodeEnv = (typeof NODE_ENVS)[number]

export interface Config {
  nodeEnv: NodeEnv
  port: number
  host: string
  databasePath: string
  /** TODO(auth): removed in Phase J, with the stub it guards. */
  allowStubAuth: boolean
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

/**
 * TODO(auth): removed in Phase J with the stub it guards.
 *
 * Set explicitly, it means exactly what it says — a misspelled value reads as
 * off, never as on. Left unset it defaults to **on outside production and off
 * in production**, which is where the guard actually earns its place: the
 * accident worth preventing is a production deploy still trusting a header
 * anyone can set, not a developer running the clinic app on a laptop.
 */
function parseAllowStubAuth(raw: string | undefined, nodeEnv: NodeEnv): boolean {
  if (raw !== undefined) return raw === 'true'
  return nodeEnv !== 'production'
}

function parseConfig(env: NodeJS.ProcessEnv): Config {
  const nodeEnv = parseNodeEnv(env.NODE_ENV)
  return {
    nodeEnv,
    port: parsePort(env.PORT),
    host: env.HOST ?? '0.0.0.0',
    databasePath: parseDatabasePath(env.DATABASE_PATH),
    allowStubAuth: parseAllowStubAuth(env.ALLOW_STUB_AUTH, nodeEnv),
  }
}

export const config: Config = parseConfig(process.env)

/** Exported for tests only: the default above is a security decision worth pinning. */
export const __parseAllowStubAuthForTest = parseAllowStubAuth
