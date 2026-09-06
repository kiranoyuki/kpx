import Fastify, { type FastifyInstance } from 'fastify'

import { readPragmas, type SqliteDatabase } from '@kpx/db'

import { assertStubAuthAllowed } from './context/principal.js'
import { registerRouteGroups, type RouteGroups } from './routes.js'
import { registerErrorHandler } from './shared/errors/handler.js'

/**
 * What the app needs from the outside. Passed in rather than imported, per
 * `conventions.md` §2 — the database handle belongs to whoever opened it
 * (main.ts in production, a test helper under test), so its lifetime is
 * managed in one place and tests need no module mocking.
 */
export interface AppDeps {
  sqlite: SqliteDatabase
  /** Must be true while authentication is the X-Acting-User stub. */
  allowStubAuth: boolean
  /** Module routes, by audience. Empty until step 16. */
  routes?: RouteGroups
  /**
   * Request logging. On by default; the test harness turns it off, because a
   * suite that prints a stack trace for every deliberate 401 is a suite nobody
   * reads.
   */
  logger?: boolean
}

// Builds a fully configured Fastify instance but never calls listen() — that
// is what makes it testable via fastify.inject() (see app.test.ts) and keeps
// main.ts the only place that binds a port.
export function buildApp(deps: AppDeps): FastifyInstance {
  const app = Fastify({ logger: deps.logger ?? true })

  // Before anything else: a server that starts while trusting a header anyone
  // can set is worse than one that does not start.
  assertStubAuthAllowed(deps.allowStubAuth)

  // Registered first, so nothing added later can escape it.
  registerErrorHandler(app)

  // Reports the pragmas rather than asserting them: `foreign_keys` is
  // per-connection and off by default, so the only trustworthy answer is the
  // one read back from this connection. `foreignKeys: false` here means a third
  // of the schema's enforcement is silently off.
  app.get('/api/health', async () => {
    const { foreignKeys, journalMode } = readPragmas(deps.sqlite)
    return { status: 'ok', foreignKeys, journalMode }
  })

  registerRouteGroups(app, deps.sqlite, deps.routes)

  return app
}
