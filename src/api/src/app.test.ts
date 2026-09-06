import { afterEach, describe, expect, it } from 'vitest'

import { createTestApi, type TestApi } from '../test/helpers/api.js'
import { createTestDatabase, type TestDatabase } from '../test/helpers/db.js'
import { buildApp } from './app.js'
import type { RoutePlugin } from './routes.js'

let api: TestApi | undefined
let db: TestDatabase | undefined

afterEach(async () => {
  await api?.close()
  db?.close()
  api = undefined
  db = undefined
})

/** A public route that reports the principal it was given. */
const reportsPrincipal: RoutePlugin = (scope) => {
  scope.get('/services', (request) => ({ principal: request.principal }))
}

describe('GET /api/health', () => {
  it('returns 200 with the status and the pragmas that gate enforcement', async () => {
    api = createTestApi()

    const response = await api.inject({ method: 'GET', url: '/api/health' })

    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual({ status: 'ok', foreignKeys: true, journalMode: 'wal' })
  })

  it('reports foreignKeys false when the connection has them off', async () => {
    api = createTestApi()
    api.db.sqlite.pragma('foreign_keys = OFF')

    const response = await api.inject({ method: 'GET', url: '/api/health' })

    expect(response.json()).toMatchObject({ foreignKeys: false })
  })
})

describe('route groups', () => {
  it('lets an anonymous caller reach a public route', async () => {
    api = createTestApi({ routes: { public: [reportsPrincipal] } })

    const response = await api.inject({ method: 'GET', url: '/api/public/services' })

    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual({ principal: { kind: 'anonymous' } })
  })

  it('ignores an acting-user header on a public route', async () => {
    // A public endpoint that quietly honoured the header would be a private
    // endpoint wearing a public prefix.
    api = createTestApi({ routes: { public: [reportsPrincipal] } })

    const response = await api.inject({
      method: 'GET',
      url: '/api/public/services',
      as: api.staffId,
    })

    expect(response.json()).toEqual({ principal: { kind: 'anonymous' } })
  })

  it('does not register /api/patient — it needs real auth, not the stub', async () => {
    api = createTestApi()

    const response = await api.inject({ method: 'GET', url: '/api/patient/me' })

    expect(response.statusCode).toBe(404)
  })
})

describe('the stub-auth guard', () => {
  it('refuses to build the app when ALLOW_STUB_AUTH is not set', () => {
    const database = (db = createTestDatabase({ seed: false }))

    expect(() => buildApp({ sqlite: database.sqlite, allowStubAuth: false })).toThrow(
      /ALLOW_STUB_AUTH/,
    )
  })

  it('names the reason, so the failure is actionable', () => {
    const database = (db = createTestDatabase({ seed: false }))

    expect(() => buildApp({ sqlite: database.sqlite, allowStubAuth: false })).toThrow(
      /X-Acting-User/,
    )
  })
})
