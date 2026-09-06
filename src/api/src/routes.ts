/**
 * The three route groups from `conventions.md` §15, and the only place a
 * principal is decided.
 *
 * Each group is an encapsulated Fastify scope with its own `onRequest` guard, so
 * a route's audience is a property of where it is registered rather than
 * something its handler has to remember. A module cannot accidentally expose a
 * clinic endpoint publicly: it would have to register it in the wrong group,
 * which is visible in one line of a diff.
 *
 * `/api/patient/*` is deliberately absent. It needs real authentication, and
 * registering it now against the stub would put patient records behind a header
 * anyone can set. It arrives in Phase J with Phase P2.
 */

import type { SqliteDatabase } from '@kpx/db'
import type { FastifyInstance } from 'fastify'

import { allowAnonymous, requireStaff } from './context/principal.js'

/** A module's routes. Modules start supplying these at step 16. */
export type RoutePlugin = (app: FastifyInstance) => void | Promise<void>

export interface RouteGroups {
  /** Staff only. Everything the internal app calls. */
  clinic?: RoutePlugin[]
  /** Unauthenticated, rate-limited. The only public write surface. */
  public?: RoutePlugin[]
}

export function registerRouteGroups(
  app: FastifyInstance,
  sqlite: SqliteDatabase,
  groups: RouteGroups = {},
): void {
  const guardStaff = requireStaff(sqlite)

  void app.register(
    async (clinic) => {
      clinic.addHook('onRequest', guardStaff)
      for (const plugin of groups.clinic ?? []) await plugin(clinic)
    },
    { prefix: '/api/clinic' },
  )

  void app.register(
    async (pub) => {
      pub.addHook('onRequest', allowAnonymous)
      for (const plugin of groups.public ?? []) await plugin(pub)
    },
    { prefix: '/api/public' },
  )
}
