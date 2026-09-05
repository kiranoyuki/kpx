import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import Sqlite from 'better-sqlite3'
import type { Kysely } from 'kysely'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { openDatabase, type SqliteDatabase } from './connection.js'
import { createTransactor, type Transactor, type Tx } from './tx.js'

/**
 * A table of its own rather than one from the real schema: these tests are
 * about the transaction boundary, and a fixture that changes when the clinic's
 * schema changes would be testing the wrong thing.
 */
interface TestDB {
  note: { id: string; body: string }
}

/** `tx.qb` is typed to the real schema, so the fixture table needs one cast. */
const q = (t: Tx): Kysely<TestDB> => t.qb as unknown as Kysely<TestDB>

let dir: string
let sqlite: SqliteDatabase
let tx: Transactor

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'kpx-tx-'))
  const path = join(dir, 'test.db')
  new Sqlite(path).close()
  sqlite = openDatabase(path)
  sqlite.exec('CREATE TABLE note (id TEXT PRIMARY KEY, body TEXT NOT NULL)')
  tx = createTransactor(sqlite)
})

afterEach(() => {
  sqlite.close()
  rmSync(dir, { recursive: true, force: true })
})

const countNotes = (): number =>
  (sqlite.prepare('SELECT count(*) AS n FROM note').get() as { n: number }).n

const insert = (t: Tx, id: string, body: string): void => {
  t.run(q(t).insertInto('note').values({ id, body }))
}

describe('write', () => {
  it('commits every row when the callback returns', () => {
    tx.write((t) => {
      insert(t, 'n1', 'one')
      insert(t, 'n2', 'two')
    })

    expect(countNotes()).toBe(2)
  })

  it('rolls back the first row when the callback throws after it', () => {
    expect(() => {
      tx.write((t) => {
        insert(t, 'n1', 'one')
        throw new Error('boom')
      })
    }).toThrow('boom')

    // The whole point: a partial write is never left behind.
    expect(countNotes()).toBe(0)
  })

  it('rolls back when the second write is the thing that fails', () => {
    expect(() => {
      tx.write((t) => {
        insert(t, 'n1', 'one')
        // Same primary key: SQLite rejects it, and the first insert goes too.
        insert(t, 'n1', 'again')
      })
    }).toThrow()

    expect(countNotes()).toBe(0)
  })

  it('returns what the callback returns', () => {
    expect(tx.write(() => 'done')).toBe('done')
  })
})

describe('the query surface', () => {
  beforeEach(() => {
    tx.write((t) => {
      insert(t, 'n1', 'one')
      insert(t, 'n2', 'two')
    })
  })

  it('all() returns every row', () => {
    const rows = tx.read((t) => t.all(q(t).selectFrom('note').selectAll()))

    expect(rows).toHaveLength(2)
  })

  it('get() returns one row', () => {
    const found = tx.read((t) => t.get(q(t).selectFrom('note').selectAll().where('id', '=', 'n1')))

    expect(found).toMatchObject({ id: 'n1', body: 'one' })
  })

  it('get() returns undefined when nothing matches', () => {
    const missing = tx.read((t) =>
      t.get(q(t).selectFrom('note').selectAll().where('id', '=', 'nope')),
    )

    expect(missing).toBeUndefined()
  })

  it('run() reports how many rows it changed', () => {
    const { changes } = tx.write((t) => t.run(q(t).deleteFrom('note').where('id', '=', 'n1')))

    expect(changes).toBe(1)
  })

  it('builds a query without executing it — nothing runs until all/get/run', () => {
    tx.read((t) => q(t).deleteFrom('note'))

    expect(countNotes()).toBe(2)
  })
})

describe('read', () => {
  it('sees rows committed by an earlier write', () => {
    tx.write((t) => {
      insert(t, 'n1', 'one')
    })

    expect(tx.read(() => countNotes())).toBe(1)
  })
})
