import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { openDatabase, Sqlite, type SqliteDatabase } from '@kpx/db'
import Fastify, { type FastifyInstance } from 'fastify'
import { afterEach, describe, expect, it } from 'vitest'

import { AppError, conflict, notFound, unprocessable } from './AppError.js'
import { registerErrorHandler } from './handler.js'

let app: FastifyInstance

afterEach(async () => {
  await app.close()
})

/** A bare app with the handler and one route that throws whatever it is given. */
function appThatThrows(thrown: unknown): FastifyInstance {
  app = Fastify({ logger: false })
  registerErrorHandler(app)
  app.get('/boom', () => {
    throw thrown
  })
  return app
}

describe('a deliberate AppError', () => {
  it('keeps its status and its code', async () => {
    const response = await appThatThrows(unprocessable('CHAIR_DOUBLE_BOOKED')).inject({
      method: 'GET',
      url: '/boom',
    })

    expect(response.statusCode).toBe(422)
    expect(response.json()).toMatchObject({ error: { code: 'CHAIR_DOUBLE_BOOKED' } })
  })

  it('carries the field when there is one to point at', async () => {
    const response = await appThatThrows(
      conflict('NATIONAL_ID_TAKEN', 'that CCCD is already registered', 'nationalId'),
    ).inject({ method: 'GET', url: '/boom' })

    expect(response.statusCode).toBe(409)
    expect(response.json()).toEqual({
      error: {
        code: 'NATIONAL_ID_TAKEN',
        message: 'that CCCD is already registered',
        field: 'nationalId',
      },
    })
  })

  it('omits field entirely rather than sending null', async () => {
    const response = await appThatThrows(notFound('PATIENT_NOT_FOUND')).inject({
      method: 'GET',
      url: '/boom',
    })

    expect(Object.keys(response.json().error)).toEqual(['code', 'message'])
  })

  it('falls back to the code as wording until the catalogue exists', async () => {
    const response = await appThatThrows(unprocessable('SOME_RULE')).inject({
      method: 'GET',
      url: '/boom',
    })

    expect(response.json().error.message).toBe('SOME_RULE')
  })
})

describe('an unexpected throw', () => {
  it('is a 500 with a fixed code', async () => {
    const response = await appThatThrows(new Error('kaboom')).inject({
      method: 'GET',
      url: '/boom',
    })

    expect(response.statusCode).toBe(500)
    expect(response.json()).toEqual({
      error: { code: 'INTERNAL', message: 'Internal server error' },
    })
  })

  it('leaks nothing from the original error', async () => {
    const leaky = new Error(
      'SQLITE_ERROR: no such column: secret_column in /Users/someone/db/kpx.db',
    )
    const response = await appThatThrows(leaky).inject({ method: 'GET', url: '/boom' })

    const body = response.payload
    expect(body).not.toContain('secret_column')
    expect(body).not.toContain('kpx.db')
    expect(body).not.toContain('/Users/')
    expect(body).not.toContain('SQLITE')
  })

  it('leaks no stack trace', async () => {
    const response = await appThatThrows(new Error('kaboom')).inject({
      method: 'GET',
      url: '/boom',
    })

    expect(response.payload).not.toContain('at ')
    expect(response.json().error).not.toHaveProperty('stack')
  })

  it('handles a thrown non-Error without falling over', async () => {
    const response = await appThatThrows('just a string').inject({ method: 'GET', url: '/boom' })

    expect(response.statusCode).toBe(500)
    expect(response.json().error.code).toBe('INTERNAL')
  })
})

describe('an unknown route', () => {
  it('answers in the same shape as every other error', async () => {
    app = Fastify({ logger: false })
    registerErrorHandler(app)

    const response = await app.inject({ method: 'GET', url: '/api/nope' })

    expect(response.statusCode).toBe(404)
    expect(response.json().error.code).toBe('NOT_FOUND')
  })
})

describe('AppError.is', () => {
  it('recognises an AppError', () => {
    expect(AppError.is(unprocessable('X'))).toBe(true)
  })

  it('rejects a plain Error, which must never be treated as deliberate', () => {
    expect(AppError.is(new Error('nope'))).toBe(false)
  })

  it('rejects a look-alike object that is not an Error', () => {
    expect(AppError.is({ code: 'FAKE', status: 422 })).toBe(false)
  })
})

/**
 * The step's Verify line, end to end: a constraint the schema still enforces
 * fires deep inside a request and has to arrive as a usable HTTP answer rather
 * than a 500.
 */
describe('a SQLite constraint reaching HTTP', () => {
  let dir: string
  let sqlite: SqliteDatabase

  function appOver(sql: string): FastifyInstance {
    dir = mkdtempSync(join(tmpdir(), 'kpx-handler-'))
    const path = join(dir, 'test.db')
    new Sqlite(path).close()
    sqlite = openDatabase(path)
    sqlite.exec(`
      CREATE TABLE owner (id TEXT PRIMARY KEY);
      CREATE TABLE thing (
        id       TEXT PRIMARY KEY,
        owner_id TEXT REFERENCES owner(id),
        email    TEXT UNIQUE,
        channel  TEXT,
        made_by  TEXT,
        CONSTRAINT ck_thing_selfmade_is_online CHECK (made_by IS NOT NULL OR channel = 'Online')
      );
    `)
    app = Fastify({ logger: false })
    registerErrorHandler(app)
    app.get('/write', () => {
      sqlite.prepare(sql).run()
      return { ok: true }
    })
    return app
  }

  afterEach(() => {
    sqlite.close()
    rmSync(dir, { recursive: true, force: true })
  })

  it('a named CHECK violation is a 422 with the constraint code', async () => {
    const response = await appOver(
      `INSERT INTO thing (id, channel, made_by) VALUES ('t1', 'FrontDesk', NULL)`,
    ).inject({ method: 'GET', url: '/write' })

    expect(response.statusCode).toBe(422)
    expect(response.json().error.code).toBe('CK_THING_SELFMADE_IS_ONLINE')
  })

  it('a foreign-key violation is a 422, not a 500', async () => {
    const response = await appOver(
      `INSERT INTO thing (id, owner_id) VALUES ('t1', 'no-such-owner')`,
    ).inject({ method: 'GET', url: '/write' })

    expect(response.statusCode).toBe(422)
    expect(response.json().error.code).toBe('REFERENCED_ROW_MISSING')
  })

  it('an unknown SQLite error is a 500 that leaks nothing', async () => {
    const response = await appOver(`INSERT INTO no_such_table (id) VALUES ('x')`).inject({
      method: 'GET',
      url: '/write',
    })

    expect(response.statusCode).toBe(500)
    expect(response.json()).toEqual({
      error: { code: 'INTERNAL', message: 'Internal server error' },
    })
    expect(response.payload).not.toContain('no_such_table')
    expect(response.payload).not.toContain('SQLITE')
  })

  it('an unnamed CHECK does not leak its predicate over the wire', async () => {
    dir = mkdtempSync(join(tmpdir(), 'kpx-handler-'))
    const path = join(dir, 'test.db')
    new Sqlite(path).close()
    sqlite = openDatabase(path)
    sqlite.exec(`CREATE TABLE t (id TEXT PRIMARY KEY, status TEXT CHECK (status IN ('Draft','Live')))`)
    app = Fastify({ logger: false })
    registerErrorHandler(app)
    app.get('/write', () => {
      sqlite.prepare(`INSERT INTO t VALUES ('x', 'Nonsense')`).run()
      return { ok: true }
    })

    const response = await app.inject({ method: 'GET', url: '/write' })

    expect(response.statusCode).toBe(422)
    expect(response.json().error.code).toBe('CONSTRAINT_VIOLATED')
    expect(response.payload).not.toContain('Draft')
  })
})
