/**
 * Every error here comes from a real SQLite write. Fabricating
 * `{ code: 'SQLITE_CONSTRAINT_CHECK', message: '…' }` would only test that the
 * regexes match strings this file made up — the failure that matters is SQLite
 * wording something differently from what the parser expects, and a fake error
 * cannot catch it.
 */

import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { openDatabase, Sqlite, type SqliteDatabase } from '@kpx/db'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import {
  CONSTRAINT_VIOLATED,
  DUPLICATE_VALUE,
  REFERENCED_ROW_MISSING,
  REQUIRED_FIELD_MISSING,
  translateSqliteError,
} from './translate.js'

let dir: string
let sqlite: SqliteDatabase

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'kpx-translate-'))
  const path = join(dir, 'test.db')
  new Sqlite(path).close()
  sqlite = openDatabase(path)
  sqlite.exec(`
    CREATE TABLE owner (id TEXT PRIMARY KEY);
    CREATE TABLE thing (
      id        TEXT PRIMARY KEY,
      owner_id  TEXT REFERENCES owner(id),
      full_name TEXT NOT NULL,
      email     TEXT UNIQUE,
      status    TEXT CHECK (status IN ('Draft', 'Live')),
      channel   TEXT,
      made_by   TEXT,
      CONSTRAINT ck_thing_selfmade_is_online CHECK (made_by IS NOT NULL OR channel = 'Online')
    );
    INSERT INTO owner VALUES ('o1');
  `)
})

afterEach(() => {
  sqlite.close()
  rmSync(dir, { recursive: true, force: true })
})

/** Runs SQL expected to fail, and hands back whatever SQLite threw. */
function thrownBy(sql: string): unknown {
  try {
    sqlite.prepare(sql).run()
  } catch (error) {
    return error
  }
  throw new Error('expected that statement to fail, but it succeeded')
}

const insert = (cols: string, vals: string): string =>
  `INSERT INTO thing (id, full_name, ${cols}) VALUES ('t1', 'A thing', ${vals})`

describe('a named ck_ constraint', () => {
  it('becomes a 422 carrying the constraint name as its code', () => {
    const error = thrownBy(insert('channel, made_by', `'FrontDesk', NULL`))

    const app = translateSqliteError(error)

    expect(app?.status).toBe(422)
    expect(app?.code).toBe('CK_THING_SELFMADE_IS_ONLINE')
  })

  it('uses the catalogue code when one is mapped, which is what step 5c supplies', () => {
    const error = thrownBy(insert('channel, made_by', `'FrontDesk', NULL`))

    const app = translateSqliteError(error, {
      ck_thing_selfmade_is_online: 'SELF_BOOKING_MUST_BE_ONLINE',
    })

    expect(app?.code).toBe('SELF_BOOKING_MUST_BE_ONLINE')
  })
})

describe('an unnamed inline CHECK', () => {
  it('becomes a generic 422 rather than a code derived from the predicate', () => {
    const error = thrownBy(insert('status', `'Nonsense'`))

    const app = translateSqliteError(error)

    expect(app?.status).toBe(422)
    expect(app?.code).toBe(CONSTRAINT_VIOLATED)
  })

  it('never lets the SQL predicate into the code or the response', () => {
    const error = thrownBy(insert('status', `'Nonsense'`))

    // SQLite reports: CHECK constraint failed: status IN ('Draft', 'Live')
    expect((error as Error).message).toContain(`status IN`)

    const app = translateSqliteError(error)
    const body = JSON.stringify(app?.toResponse())
    expect(body).not.toContain('Draft')
    expect(body).not.toContain('IN (')
  })
})

describe('a foreign key violation', () => {
  it('is a 422, not a 500 — the row referenced does not exist', () => {
    const error = thrownBy(insert('owner_id', `'no-such-owner'`))

    const app = translateSqliteError(error)

    expect(app?.status).toBe(422)
    expect(app?.code).toBe(REFERENCED_ROW_MISSING)
  })

  it('points at no field, because SQLite names neither key nor table', () => {
    const error = thrownBy(insert('owner_id', `'no-such-owner'`))

    expect((error as Error).message).toBe('FOREIGN KEY constraint failed')
    expect(translateSqliteError(error)?.field).toBeUndefined()
  })
})

describe('a uniqueness violation', () => {
  it('is a 409 naming the offending field in camelCase', () => {
    sqlite.prepare(insert('email', `'a@b.c'`)).run()
    const error = thrownBy(
      `INSERT INTO thing (id, full_name, email) VALUES ('t2', 'Another', 'a@b.c')`,
    )

    const app = translateSqliteError(error)

    expect(app?.status).toBe(409)
    expect(app?.code).toBe(DUPLICATE_VALUE)
    expect(app?.field).toBe('email')
  })

  it('reports a duplicate primary key as a 409 too', () => {
    sqlite.prepare(insert('email', `'a@b.c'`)).run()
    const error = thrownBy(`INSERT INTO thing (id, full_name) VALUES ('t1', 'Clash')`)

    expect(translateSqliteError(error)?.status).toBe(409)
  })
})

describe('a NOT NULL violation', () => {
  it('is a 422 naming the column, converted to camelCase', () => {
    const error = thrownBy(`INSERT INTO thing (id, channel) VALUES ('t3', 'Online')`)

    const app = translateSqliteError(error)

    expect(app?.status).toBe(422)
    expect(app?.code).toBe(REQUIRED_FIELD_MISSING)
    expect(app?.field).toBe('fullName')
  })
})

describe('anything else', () => {
  it('leaves a SQLite error it does not recognise untranslated', () => {
    const error = thrownBy(`INSERT INTO no_such_table (id) VALUES ('x')`)

    // SQLITE_ERROR: a bug, not a refusal. Undefined here means the handler
    // reports 500 rather than dressing a fault up as something to fix.
    expect(translateSqliteError(error)).toBeUndefined()
  })

  it('leaves an ordinary Error alone', () => {
    expect(translateSqliteError(new Error('kaboom'))).toBeUndefined()
  })

  it('leaves a non-Error alone', () => {
    expect(translateSqliteError('nope')).toBeUndefined()
  })

  it('never attaches the SQLite message as user-facing wording', () => {
    const error = thrownBy(insert('owner_id', `'no-such-owner'`))

    // The code is the contract; wording arrives from the catalogue in 5c.
    expect(translateSqliteError(error)?.toResponse().error.message).toBe(REFERENCED_ROW_MISSING)
  })
})
