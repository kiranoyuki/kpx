import Database from 'better-sqlite3'
import { Kysely, SqliteDialect } from 'kysely'

import type { DB } from './schema.js'

/**
 * The better-sqlite3 instance type. The package is `export =`, so the instance
 * type hangs off the imported class rather than being a separate named export.
 */
export type SqliteDatabase = Database.Database

/**
 * How long a blocked writer waits for the lock before failing with SQLITE_BUSY.
 *
 * Under `conventions.md` §3 exactly one process writes this file, so in
 * production nothing should ever contend. It matters in development, where a
 * SQL client attached to the same file is a second connection, and during a
 * `db/build.sh` rebuild.
 */
const BUSY_TIMEOUT_MS = 5000

/**
 * Applied once per connection, at open.
 *
 * `foreign_keys` is the one that earns the health check. It is **off by
 * default** and it is **per-connection** — it is not stored in the file, so a
 * connection that forgets it silently disables all 108 foreign keys. Nothing
 * errors; writes simply stop being checked. That failure is invisible from
 * inside the application, which is why `/api/health` reports the value read
 * back from SQLite rather than trusting that this function ran.
 *
 * `journal_mode = WAL` is the exception: it is a property of the database file
 * and persists across connections. The other three are per-connection.
 *
 * `synchronous = NORMAL` is the documented pairing for WAL — it is safe against
 * application crashes, and risks only the most recent commits on an OS-level
 * crash or power loss.
 */
export function applyPragmas(sqlite: SqliteDatabase): void {
  sqlite.pragma('foreign_keys = ON')
  sqlite.pragma('journal_mode = WAL')
  sqlite.pragma(`busy_timeout = ${String(BUSY_TIMEOUT_MS)}`)
  sqlite.pragma('synchronous = NORMAL')
}

export interface PragmaReport {
  foreignKeys: boolean
  journalMode: string
}

/**
 * Reads back the two pragmas worth reporting, so a caller can prove enforcement
 * is on rather than assume it. Read from SQLite every time: these are cheap, and
 * a cached answer would defeat the purpose.
 */
export function readPragmas(sqlite: SqliteDatabase): PragmaReport {
  return {
    foreignKeys: sqlite.pragma('foreign_keys', { simple: true }) === 1,
    journalMode: String(sqlite.pragma('journal_mode', { simple: true })),
  }
}

/**
 * Opens the one long-lived handle to an **existing** database.
 *
 * `fileMustExist` is deliberate. better-sqlite3 creates an empty database when
 * the path does not exist, so without it a mistyped `DATABASE_PATH` boots the
 * API against a database with no tables — and the first failure surfaces much
 * later, as a confusing "no such table" on an unrelated request. The schema is
 * built by `db/build.sh` from the module files; the API never creates it.
 */
export function openDatabase(filename: string): SqliteDatabase {
  const sqlite = new Database(filename, { fileMustExist: true })
  applyPragmas(sqlite)
  return sqlite
}

/**
 * Wraps an open handle in Kysely. Kysely owns query building and types; it does
 * not own the connection, so the caller keeps the handle and closes it.
 */
export function createKysely(sqlite: SqliteDatabase): Kysely<DB> {
  return new Kysely<DB>({ dialect: new SqliteDialect({ database: sqlite }) })
}
