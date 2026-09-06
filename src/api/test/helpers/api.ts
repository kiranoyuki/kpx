/**
 * An app wired to a throwaway database, with `inject` instead of a port.
 *
 * `buildApp` never listens (step 1), so these tests exercise the real routing,
 * the real error handler and the real principal guard without binding anything.
 *
 * The two ids below come from the seed rather than being invented, because the
 * seed's people are the interesting ones: `staffId` reaches the staff portal,
 * and `departedStaffId` is a doctor who left the clinic and is still an Active
 * patient — the row a naive authorisation check gets wrong.
 */

import type { FastifyInstance, InjectOptions, LightMyRequestResponse } from 'fastify'

import { buildApp } from '../../src/app.js'
import { ACTING_USER_HEADER } from '../../src/context/principal.js'
import type { RouteGroups } from '../../src/routes.js'
import { createTestDatabase, type TestDatabase, type TestDatabaseOptions } from './db.js'

/** `inject`, plus `as` for the acting user. Omit `as` to call anonymously. */
export type TestInjectOptions = InjectOptions & { as?: string }

export interface TestApi {
  app: FastifyInstance
  db: TestDatabase
  /** A seeded id that reaches the staff portal. */
  staffId: string
  /** A seeded id that does not — departed, but still a patient. */
  departedStaffId: string
  inject: (options: TestInjectOptions) => Promise<LightMyRequestResponse>
  close: () => Promise<void>
}

export interface TestApiOptions extends TestDatabaseOptions {
  /** Routes under test, by audience. Modules supply these from step 16. */
  routes?: RouteGroups
  /** Default true. Set false to assert the app refuses to start. */
  allowStubAuth?: boolean
  /** Default false here — pass true when debugging a single test. */
  logger?: boolean
}

function idFromView(db: TestDatabase, where: string): string {
  const row = db.sqlite
    .prepare(`SELECT id FROM v_portal_access WHERE ${where} LIMIT 1`)
    .get() as { id: string } | undefined
  if (row === undefined) {
    throw new Error(`the seed has nobody matching "${where}" — has 0109_people_access_seed.sql changed?`)
  }
  return row.id
}

export function createTestApi(options: TestApiOptions = {}): TestApi {
  const db = createTestDatabase(options)
  const app = buildApp({
    sqlite: db.sqlite,
    allowStubAuth: options.allowStubAuth ?? true,
    routes: options.routes,
    logger: options.logger ?? false,
  })

  return {
    app,
    db,
    staffId: idFromView(db, "staff_portal = 'yes'"),
    departedStaffId: idFromView(db, "employment = 'Departed'"),
    inject: async ({ as, headers, ...rest }: TestInjectOptions) =>
      app.inject({
        ...rest,
        headers: as === undefined ? headers : { ...headers, [ACTING_USER_HEADER]: as },
      }),
    close: async () => {
      await app.close()
      db.close()
    },
  }
}
