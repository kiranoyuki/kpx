import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import Database from 'better-sqlite3'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { buildApp } from './app.js'
import { openDatabase, type SqliteDatabase } from './db/connection.js'

let dir: string
let sqlite: SqliteDatabase

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'kpx-app-'))
  const path = join(dir, 'test.db')
  new Database(path).close()
  sqlite = openDatabase(path)
})

afterEach(() => {
  sqlite.close()
  rmSync(dir, { recursive: true, force: true })
})

describe('GET /api/health', () => {
  it('returns 200 with the status and the pragmas that gate enforcement', async () => {
    const app = buildApp({ sqlite })

    const response = await app.inject({ method: 'GET', url: '/api/health' })

    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual({ status: 'ok', foreignKeys: true, journalMode: 'wal' })

    await app.close()
  })

  it('reports foreignKeys false when the connection has them off', async () => {
    sqlite.pragma('foreign_keys = OFF')
    const app = buildApp({ sqlite })

    const response = await app.inject({ method: 'GET', url: '/api/health' })

    expect(response.json()).toMatchObject({ foreignKeys: false })

    await app.close()
  })
})
