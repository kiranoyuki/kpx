import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { openDatabase, Sqlite, type SqliteDatabase } from '@kpx/db'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { buildApp } from './app.js'

let dir: string
let sqlite: SqliteDatabase

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'kpx-app-'))
  const path = join(dir, 'test.db')
  new Sqlite(path).close()
  sqlite = openDatabase(path)
})

afterEach(() => {
  sqlite.close()
  rmSync(dir, { recursive: true, force: true })
})

describe('GET /api/health', () => {
  it('returns 200 with the status and the pragmas that gate enforcement', async () => {
    const app = buildApp({ sqlite, allowStubAuth: true })

    const response = await app.inject({ method: 'GET', url: '/api/health' })

    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual({ status: 'ok', foreignKeys: true, journalMode: 'wal' })

    await app.close()
  })

  it('reports foreignKeys false when the connection has them off', async () => {
    sqlite.pragma('foreign_keys = OFF')
    const app = buildApp({ sqlite, allowStubAuth: true })

    const response = await app.inject({ method: 'GET', url: '/api/health' })

    expect(response.json()).toMatchObject({ foreignKeys: false })

    await app.close()
  })
})

describe('route groups', () => {
  it('lets an anonymous caller reach a public route', async () => {
    const app = buildApp({
      sqlite,
      allowStubAuth: true,
      routes: {
        public: [
          (scope) => {
            scope.get('/services', (request) => ({ principal: request.principal }))
          },
        ],
      },
    })

    const response = await app.inject({ method: 'GET', url: '/api/public/services' })

    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual({ principal: { kind: 'anonymous' } })
    await app.close()
  })

  it('ignores an acting-user header on a public route', async () => {
    // A public endpoint that quietly honoured the header would be a private
    // endpoint wearing a public prefix.
    const app = buildApp({
      sqlite,
      allowStubAuth: true,
      routes: {
        public: [
          (scope) => {
            scope.get('/services', (request) => ({ principal: request.principal }))
          },
        ],
      },
    })

    const response = await app.inject({
      method: 'GET',
      url: '/api/public/services',
      headers: { 'x-acting-user': 'active' },
    })

    expect(response.json()).toEqual({ principal: { kind: 'anonymous' } })
    await app.close()
  })

  it('does not register /api/patient — it needs real auth, not the stub', async () => {
    const app = buildApp({ sqlite, allowStubAuth: true })

    const response = await app.inject({ method: 'GET', url: '/api/patient/me' })

    expect(response.statusCode).toBe(404)
    await app.close()
  })
})

describe('the stub-auth guard', () => {
  it('refuses to build the app when ALLOW_STUB_AUTH is not set', () => {
    expect(() => buildApp({ sqlite, allowStubAuth: false })).toThrow(/ALLOW_STUB_AUTH/)
  })

  it('names the reason, so the failure is actionable', () => {
    expect(() => buildApp({ sqlite, allowStubAuth: false })).toThrow(/X-Acting-User/)
  })
})
