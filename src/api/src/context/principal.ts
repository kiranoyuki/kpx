/**
 * Who is making this request.
 *
 * TODO(auth): every line below is a stub. It trusts an `X-Acting-User` header,
 * which anyone can set, and it exists only so the rest of the backend can be
 * built and tested before real authentication lands in Phase J. It refuses to
 * run unless `ALLOW_STUB_AUTH=true`, so it cannot be deployed by accident.
 *
 * ## A principal, not an acting user
 *
 * `conventions.md` §15: three kinds of caller exist, and the **route group**
 * decides which is required — not the handler, and never the data.
 *
 * | Group           | Principal                    |
 * |-----------------|------------------------------|
 * | `/api/clinic/*` | `staff`, required            |
 * | `/api/public/*` | `anonymous`                  |
 * | `/api/patient/*`| `patient` — Phase J          |
 *
 * ## Staff means the staff portal, not a row in app_user
 *
 * Authorisation asks `v_portal_access`, which already encodes the answer:
 * `app_user.status = 'Active'` **and** a `staff_profile` exists **and** its
 * `employment_status` is `Intern` or `Active`.
 *
 * "Does an `app_user` row exist?" is the tempting shortcut and it is wrong. The
 * seed data contains a **Departed doctor who is still an Active patient** — the
 * separation the schema exists to express. That row would pass the shortcut and
 * would let someone who has left the clinic keep acting as staff. An OnLeave
 * doctor is the same story. Interns *do* reach the staff portal; the difference
 * from Active is terms, not access.
 *
 * Deriving that here in TypeScript instead would mean two copies of the rule,
 * drifting apart the first time employment statuses change.
 */

import { type SqliteDatabase } from '@kpx/db'
import type { FastifyRequest, onRequestHookHandler } from 'fastify'

import { unauthorized } from '../shared/errors/AppError.js'

export const ACTING_USER_HEADER = 'x-acting-user'

/** The single code for every refusal below — see `refuse` for why. */
export const STAFF_AUTH_REQUIRED = 'STAFF_AUTH_REQUIRED'

export type Principal =
  | { kind: 'staff'; userId: string }
  | { kind: 'patient'; userId: string }
  | { kind: 'anonymous' }

declare module 'fastify' {
  interface FastifyRequest {
    principal: Principal
  }
}

export interface PortalAccess {
  staff: boolean
  patient: boolean
}

interface PortalAccessRow {
  staff_portal: string
  patient_portal: string
}

/**
 * Asks the view, so the rule lives in exactly one place. Returns undefined when
 * there is no such person at all.
 */
export function lookupPortalAccess(
  sqlite: SqliteDatabase,
  userId: string,
): PortalAccess | undefined {
  const row = sqlite
    .prepare('SELECT staff_portal, patient_portal FROM v_portal_access WHERE id = ?')
    .get(userId) as PortalAccessRow | undefined

  if (row === undefined) return undefined
  return { staff: row.staff_portal === 'yes', patient: row.patient_portal === 'yes' }
}

/**
 * One code and one message for "no header", "unknown id" and "not staff".
 *
 * Distinct codes would tell an unauthenticated caller which user ids exist,
 * which is a question they have no business asking. The specific reason goes to
 * the log, where the people who need it can see it.
 */
function refuse(request: FastifyRequest, reason: string): never {
  request.log.warn({ reason }, 'staff authorisation refused')
  throw unauthorized(STAFF_AUTH_REQUIRED)
}

/**
 * `onRequest` guard for `/api/clinic/*`. Resolves the principal and refuses
 * anything that is not staff.
 */
export function requireStaff(sqlite: SqliteDatabase): onRequestHookHandler {
  return function staffGuard(request, _reply, done) {
    const header = request.headers[ACTING_USER_HEADER]
    const userId = Array.isArray(header) ? header[0] : header

    if (userId === undefined || userId.trim() === '') {
      refuse(request, 'no X-Acting-User header')
    }

    const access = lookupPortalAccess(sqlite, userId)
    if (access === undefined) {
      refuse(request, 'X-Acting-User names nobody')
    }
    if (!access.staff) {
      // Departed, OnLeave, not-yet-Active, or simply a patient.
      refuse(request, 'that person does not reach the staff portal')
    }

    request.principal = { kind: 'staff', userId }
    done()
  }
}

/**
 * `onRequest` guard for `/api/public/*`. Reads no auth header at all: anonymous
 * is the expected principal there, and a public endpoint that quietly honoured a
 * header would be a private endpoint wearing a public prefix.
 */
export const allowAnonymous: onRequestHookHandler = function anonymousGuard(request, _reply, done) {
  request.principal = { kind: 'anonymous' }
  done()
}

/**
 * Refuses to let the application start with stub auth unless it has been asked
 * for explicitly. Failing to boot is the point: a server that starts and trusts
 * a header is worse than one that does not start.
 */
export function assertStubAuthAllowed(allowStubAuth: boolean): void {
  if (!allowStubAuth) {
    throw new Error(
      'Refusing to start: authentication is still the X-Acting-User stub, which trusts a ' +
        'header anyone can set. Set ALLOW_STUB_AUTH=true to run it deliberately. ' +
        'Real authentication arrives in Phase J.',
    )
  }
}
