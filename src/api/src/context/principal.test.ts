/**
 * These run against the **real** `v_portal_access` definition, applied from
 * `db/modules/0101_people_access_schema.sql` into a temp database. The view is
 * the thing being trusted — reimplementing its logic in a fixture would test a
 * copy of the rule rather than the rule.
 *
 * The rows mirror the seed's genuinely awkward people, because they are what
 * the naive check gets wrong:
 *
 * | person            | app_user.status | employment | staff portal |
 * |-------------------|-----------------|------------|--------------|
 * | active doctor     | Active          | Active     | yes          |
 * | intern            | Active          | Intern     | yes          |
 * | **departed**      | **Active**      | Departed   | **no**       |
 * | on leave          | Active          | OnLeave    | no           |
 * | plain patient     | Active          | —          | no           |
 */

import { readFileSync } from 'node:fs'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { openDatabase, Sqlite, type SqliteDatabase } from '@kpx/db'
import Fastify, { type FastifyInstance } from 'fastify'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { registerErrorHandler } from '../shared/errors/handler.js'
import {
  ACTING_USER_HEADER,
  assertStubAuthAllowed,
  lookupPortalAccess,
  requireStaff,
  STAFF_AUTH_REQUIRED,
} from './principal.js'

const PEOPLE_SCHEMA = join(import.meta.dirname, '../../../../db/modules/0101_people_access_schema.sql')

let dir: string
let sqlite: SqliteDatabase
let app: FastifyInstance

/** `(id, status, employment)` — employment null means "not staff at all". */
function addPerson(id: string, status: string, employment: string | null): void {
  const verified =
    status === 'Active' ? `'2026-01-01T00:00:00Z', 'seed'` : `NULL, NULL`
  sqlite
    .prepare(
      `INSERT INTO app_user (id, full_name, phone, role, status, verified_at, verified_by)
       VALUES (?, ?, ?, 'Doctor', ?, ${verified})`,
    )
    .run(id, `Person ${id}`, `09${id.padStart(8, '0')}`.slice(0, 10), status)

  if (employment === null) {
    sqlite
      .prepare(
        `INSERT INTO patient_profile (id, user_id, created_by) VALUES (?, ?, 'seed')`,
      )
      .run(`pp-${id}`, id)
    return
  }
  const endDate = employment === 'Departed' ? `'2026-06-01'` : 'NULL'
  sqlite
    .prepare(
      `INSERT INTO staff_profile (id, user_id, employment_status, join_date, end_date)
       VALUES (?, ?, ?, '2025-01-01', ${endDate})`,
    )
    .run(`sp-${id}`, id, employment)
}

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'kpx-principal-'))
  const path = join(dir, 'test.db')
  new Sqlite(path).close()
  sqlite = openDatabase(path)
  sqlite.exec(readFileSync(PEOPLE_SCHEMA, 'utf8'))

  sqlite.prepare(`INSERT INTO app_user (id, full_name, phone, role, status)
                  VALUES ('seed', 'Seed', '0900000000', 'Manager', 'Provisional')`).run()
  addPerson('active', 'Active', 'Active')
  addPerson('intern', 'Active', 'Intern')
  addPerson('departed', 'Active', 'Departed')
  // Like Ngô Bảo Châu in the seed: left the clinic, still a patient here. The
  // whole reason portals come from profiles rather than from `role`.
  sqlite
    .prepare(`INSERT INTO patient_profile (id, user_id, created_by)
              VALUES ('pp-departed', 'departed', 'seed')`)
    .run()
  addPerson('onleave', 'Active', 'OnLeave')
  addPerson('patient', 'Active', null)

  app = Fastify({ logger: false })
  registerErrorHandler(app)
  void app.register(
    async (clinic) => {
      clinic.addHook('onRequest', requireStaff(sqlite))
      clinic.get('/thing', (request) => ({ principal: request.principal }))
    },
    { prefix: '/api/clinic' },
  )
})

afterEach(async () => {
  await app.close()
  sqlite.close()
  rmSync(dir, { recursive: true, force: true })
})

const asUser = async (id?: string): Promise<ReturnType<FastifyInstance['inject']>> =>
  app.inject({
    method: 'GET',
    url: '/api/clinic/thing',
    headers: id === undefined ? {} : { [ACTING_USER_HEADER]: id },
  })

describe('a clinic route', () => {
  it('lets an Active staff member through, and names them', async () => {
    const response = await asUser('active')

    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual({ principal: { kind: 'staff', userId: 'active' } })
  })

  it('lets an Intern through — the difference from Active is terms, not access', async () => {
    expect((await asUser('intern')).statusCode).toBe(200)
  })

  it('refuses a request with no header', async () => {
    const response = await asUser()

    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe(STAFF_AUTH_REQUIRED)
  })

  it('refuses an id that names nobody', async () => {
    expect((await asUser('no-such-person')).statusCode).toBe(401)
  })

  it('refuses a DEPARTED staff member whose app_user row is still Active', async () => {
    // The case a "does the row exist?" check gets wrong, and the reason this
    // guard asks the view instead.
    expect((await asUser('departed')).statusCode).toBe(401)
  })

  it('refuses an OnLeave doctor', async () => {
    expect((await asUser('onleave')).statusCode).toBe(401)
  })

  it('refuses a patient', async () => {
    expect((await asUser('patient')).statusCode).toBe(401)
  })

  it('gives the same code whether the id is unknown or merely not staff', async () => {
    // Distinct codes would confirm which user ids exist to a caller who has not
    // authenticated at all.
    const unknown = await asUser('no-such-person')
    const notStaff = await asUser('patient')

    expect(unknown.json()).toEqual(notStaff.json())
  })

  it('refuses a blank header rather than treating it as absent-but-fine', async () => {
    expect((await asUser('   ')).statusCode).toBe(401)
  })
})

describe('lookupPortalAccess', () => {
  it('reports both portals for a doctor who is also a patient', () => {
    addPerson('both', 'Active', 'Active')
    sqlite
      .prepare(`INSERT INTO patient_profile (id, user_id, created_by) VALUES ('pp-both','both','seed')`)
      .run()

    expect(lookupPortalAccess(sqlite, 'both')).toEqual({ staff: true, patient: true })
  })

  it('keeps the patient portal for a departed doctor', () => {
    // Employment ends on staff_profile; the person continues on app_user.
    expect(lookupPortalAccess(sqlite, 'departed')).toEqual({ staff: false, patient: true })
  })

  it('returns undefined for someone who does not exist', () => {
    expect(lookupPortalAccess(sqlite, 'nobody')).toBeUndefined()
  })
})

describe('assertStubAuthAllowed', () => {
  it('throws when the flag is not set', () => {
    expect(() => {
      assertStubAuthAllowed(false)
    }).toThrow(/ALLOW_STUB_AUTH/)
  })

  it('passes when it is', () => {
    expect(() => {
      assertStubAuthAllowed(true)
    }).not.toThrow()
  })
})
