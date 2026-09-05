import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import Database from 'better-sqlite3'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { openDatabase, readPragmas, type SqliteDatabase } from './connection.js'

// A real file, not ':memory:'. An in-memory database cannot use WAL — it
// reports journal_mode 'memory' — so it could not prove the pragma applied.
let dir: string
let path: string
let sqlite: SqliteDatabase | undefined

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'kpx-conn-'))
  path = join(dir, 'test.db')
  // openDatabase refuses to create, so the file has to exist first.
  new Database(path).close()
})

afterEach(() => {
  sqlite?.close()
  sqlite = undefined
  rmSync(dir, { recursive: true, force: true })
})

describe('openDatabase', () => {
  it('turns foreign keys on — they are off by default and per-connection', () => {
    sqlite = openDatabase(path)

    expect(sqlite.pragma('foreign_keys', { simple: true })).toBe(1)
  })

  it('puts the database in WAL mode', () => {
    sqlite = openDatabase(path)

    expect(sqlite.pragma('journal_mode', { simple: true })).toBe('wal')
  })

  it('sets busy_timeout to 5000ms', () => {
    sqlite = openDatabase(path)

    expect(sqlite.pragma('busy_timeout', { simple: true })).toBe(5000)
  })

  it('sets synchronous to NORMAL (1), the documented pairing for WAL', () => {
    sqlite = openDatabase(path)

    expect(sqlite.pragma('synchronous', { simple: true })).toBe(1)
  })

  it('refuses a path that does not exist instead of creating an empty database', () => {
    const missing = join(dir, 'no-such.db')

    expect(() => openDatabase(missing)).toThrow()
  })

  it('enforces a foreign key, proving the pragma is not merely reported', () => {
    sqlite = openDatabase(path)
    sqlite.exec(`
      CREATE TABLE parent (id TEXT PRIMARY KEY);
      CREATE TABLE child  (id TEXT PRIMARY KEY, parent_id TEXT REFERENCES parent(id));
    `)

    expect(() => {
      sqlite?.prepare('INSERT INTO child VALUES (?, ?)').run('c1', 'nope')
    }).toThrow(/FOREIGN KEY constraint failed/)
  })
})

describe('readPragmas', () => {
  it('reports what the connection actually has set', () => {
    sqlite = openDatabase(path)

    expect(readPragmas(sqlite)).toEqual({ foreignKeys: true, journalMode: 'wal' })
  })

  it('reports foreignKeys false when they are off, rather than assuming', () => {
    sqlite = openDatabase(path)
    sqlite.pragma('foreign_keys = OFF')

    expect(readPragmas(sqlite).foreignKeys).toBe(false)
  })
})
