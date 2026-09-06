import { afterEach, describe, expect, it } from 'vitest'

import { FixedClock } from '../../src/shared/clock.js'
import { SeqIds } from '../../src/shared/ids.js'
import { clinicDateOf, clinicTimeOf } from '../../src/shared/time.js'
import { createTestApi, TEST_NOW, type TestApi } from './api.js'
import { createTestDatabase, type TestDatabase } from './db.js'

const open: (TestDatabase | TestApi)[] = []
const track = <T extends TestDatabase | TestApi>(x: T): T => {
  open.push(x)
  return x
}

afterEach(async () => {
  for (const x of open.splice(0)) await x.close()
})

describe('createTestDatabase', () => {
  it('carries the whole schema, not a fixture subset', () => {
    const db = track(createTestDatabase())

    const counts = db.sqlite
      .prepare(
        `SELECT (SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%') AS tables,
                (SELECT count(*) FROM sqlite_master WHERE type='view')  AS views`,
      )
      .get() as { tables: number; views: number }

    expect(counts.tables).toBe(43)
    expect(counts.views).toBe(37)
  })

  it('is seeded by default, including the awkward people', () => {
    const db = track(createTestDatabase())

    const departed = db.sqlite
      .prepare("SELECT count(*) AS n FROM v_portal_access WHERE employment = 'Departed'")
      .get() as { n: number }

    expect(departed.n).toBeGreaterThan(0)
  })

  it('can be schema-only when a test wants to control every row', () => {
    const db = track(createTestDatabase({ seed: false }))

    const people = db.sqlite.prepare('SELECT count(*) AS n FROM app_user').get() as { n: number }

    expect(people.n).toBe(0)
  })

  it('applies the production pragmas — foreign keys above all', () => {
    const db = track(createTestDatabase())

    expect(db.sqlite.pragma('foreign_keys', { simple: true })).toBe(1)
  })

  it('enforces foreign keys, so a passing test means something', () => {
    const db = track(createTestDatabase())

    expect(() => {
      db.sqlite
        .prepare(`INSERT INTO patient_profile (id, user_id, created_by) VALUES ('x','nobody','nobody')`)
        .run()
    }).toThrow(/FOREIGN KEY/)
  })

  it('hands over a working transactor that rolls back', () => {
    const db = track(createTestDatabase({ seed: false }))

    expect(() => {
      db.tx.write((t) => {
        t.run(
          t.qb
            .insertInto('app_user')
            .values({ id: 'r1', full_name: 'R', phone: '0900000009', role: 'Patient', status: 'Provisional' }),
        )
        throw new Error('boom')
      })
    }).toThrow('boom')

    const n = db.sqlite.prepare('SELECT count(*) AS n FROM app_user').get() as { n: number }
    expect(n.n).toBe(0)
  })

  it('gives two databases in the same file separate storage', () => {
    const one = track(createTestDatabase({ seed: false }))
    const two = track(createTestDatabase({ seed: false }))

    one.sqlite
      .prepare(`INSERT INTO app_user (id, full_name, phone, role, status)
                VALUES ('dup', 'One', '0900000001', 'Patient', 'Provisional')`)
      .run()

    expect(one.path).not.toBe(two.path)
    const n = two.sqlite.prepare("SELECT count(*) AS n FROM app_user WHERE id='dup'").get() as { n: number }
    expect(n.n).toBe(0)
  })
})

describe('createTestApi', () => {
  it('serves health against its own database', async () => {
    const api = track(createTestApi())

    const response = await api.inject({ method: 'GET', url: '/api/health' })

    expect(response.statusCode).toBe(200)
    expect(response.json()).toMatchObject({ foreignKeys: true })
  })

  it('resolves real seed ids rather than hard-coded ones', () => {
    const api = track(createTestApi())

    expect(api.staffId).toMatch(/\S/)
    expect(api.departedStaffId).not.toBe(api.staffId)
  })

  it('lets a staff member through a clinic route', async () => {
    const api = track(
      createTestApi({ routes: { clinic: [(s) => { s.get('/probe', () => ({ ok: true })) }] } }),
    )

    const response = await api.inject({ method: 'GET', url: '/api/clinic/probe', as: api.staffId })

    expect(response.statusCode).toBe(200)
  })

  it('refuses the departed doctor, and an anonymous caller', async () => {
    const api = track(
      createTestApi({ routes: { clinic: [(s) => { s.get('/probe', () => ({ ok: true })) }] } }),
    )

    const departed = await api.inject({
      method: 'GET', url: '/api/clinic/probe', as: api.departedStaffId,
    })
    const anonymous = await api.inject({ method: 'GET', url: '/api/clinic/probe' })

    expect(departed.statusCode).toBe(401)
    expect(anonymous.statusCode).toBe(401)
  })
})

/**
 * Step 9's Verify. Until step 15 there is no use case, but the path is the one a
 * use case will take: Fastify resolves the dependency, the route unpacks it, and
 * the handler works with plain values — no Fastify type below this line.
 */
describe('injected clock and ids', () => {
  it('a handler reads exactly the moment the test fixed', async () => {
    const api = track(
      createTestApi({
        clock: FixedClock('2026-09-04T10:00:00Z'),
        routes: {
          clinic: [
            (scope) => {
              const { clock } = scope
              scope.get('/now', () => ({ now: clock.now(), clinicTime: clinicTimeOf(clock.now()) }))
            },
          ],
        },
      }),
    )

    const response = await api.inject({ method: 'GET', url: '/api/clinic/now', as: api.staffId })

    expect(response.json()).toEqual({
      // Stored UTC; rendered in clinic time only for display.
      now: '2026-09-04T10:00:00.000Z',
      clinicTime: '17:00',
    })
  })

  it('ids are sequential, so a test can name the row it expects', async () => {
    const api = track(
      createTestApi({
        ids: SeqIds('appt'),
        routes: {
          clinic: [
            (scope) => {
              const { ids } = scope
              scope.get('/id', () => ({ id: ids.next() }))
            },
          ],
        },
      }),
    )

    expect((await api.inject({ method: 'GET', url: '/api/clinic/id', as: api.staffId })).json())
      .toEqual({ id: 'appt-1' })
    expect((await api.inject({ method: 'GET', url: '/api/clinic/id', as: api.staffId })).json())
      .toEqual({ id: 'appt-2' })
  })

  it('defaults to a fixed clock, so no test depends on the day it runs', () => {
    const api = track(createTestApi())

    expect(api.clock.now()).toBe(new Date(TEST_NOW).toISOString())
    expect(clinicDateOf(api.clock.now())).toBe('2026-09-04')
    expect(api.ids.next()).toBe('test-1')
  })
})
