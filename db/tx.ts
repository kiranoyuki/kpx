/**
 * The transaction boundary. Every write in the system goes through `write()`;
 * nothing else opens a transaction (`conventions.md` §3).
 *
 * ## A transaction may contain only these
 *
 * ```
 * write()
 *  ├── read from the database
 *  ├── evaluate business rules (domain/, shared/)
 *  ├── write to the database
 *  └── commit
 * ```
 *
 * ## Never, inside a transaction
 *
 * ```
 * ✗ await — of any kind
 * ✗ an HTTP call or external API
 * ✗ sending email or SMS
 * ✗ reading or writing a file
 * ✗ a timer, a queue publish, a cache call
 * ```
 *
 * One `await` splits the sync block and reopens every check-then-act race.
 * ESLint enforces the `await` half of that list; the rest is review.
 *
 * ## Why the callback is synchronous, and why Kysely does not execute here
 *
 * `better-sqlite3` is synchronous and Node is single-threaded, so a sync
 * transaction is atomic against other requests **in this process**. That
 * property is what replaced the 56 removed triggers, and it survives only as
 * long as the callback never yields.
 *
 * Kysely's own execute API returns a Promise, so using it would require an
 * `await` on every query — exactly what the rule above forbids. So Kysely is
 * used for what it is good at, **building typed SQL**, and `.compile()` hands
 * the statement to `better-sqlite3` to run synchronously. Type safety is kept;
 * the yield is not.
 *
 * ## The deployment invariant this rests on
 *
 * ```
 * Exactly one application process may write to db/kpx.db.
 * ```
 *
 * This is an architectural constraint, not a distributed-concurrency solution.
 * Two processes would interleave check and write and the guarantee is gone,
 * without a single test failing. See `conventions.md` §3 before adding a second
 * writer of any kind — a cron worker, a blue/green overlap, horizontal scaling.
 */

import type { Compilable } from 'kysely'

import { createKysely, type SqliteDatabase } from './connection.js'
import type { DB } from './schema.js'
import type { Kysely } from 'kysely'

/**
 * The synchronous query surface handed to a `read()` or `write()` callback.
 *
 * `qb` builds; `all` / `get` / `run` execute. Nothing runs until one of the
 * three is called, so a query builder left unexecuted is a no-op rather than a
 * silent pending Promise.
 */
export interface Tx {
  /** Kysely, for **building** queries. Never call `.execute()` on it. */
  readonly qb: Kysely<DB>
  /** Every matching row. */
  all<O>(query: Compilable<O>): O[]
  /** The first row, or undefined. */
  get<O>(query: Compilable<O>): O | undefined
  /** An insert, update or delete. Returns the number of rows affected. */
  run(query: Compilable<unknown>): { changes: number }
}

export interface Transactor {
  /**
   * A read outside any transaction. Reads that make a business decision still
   * go through domain code — a `GET` is not a licence to move rules into SQL
   * (`conventions.md` §2).
   */
  read<T>(fn: (tx: Tx) => T): T
  /**
   * One transaction. Commits when `fn` returns, rolls back if it throws.
   *
   * `fn` must be synchronous. It is typed to return `T` rather than
   * `Promise<T>`, so returning a Promise is a type error rather than a
   * transaction that commits before its work finishes.
   */
  write<T>(fn: (tx: Tx) => T): T
}

/**
 * Binds the transaction helpers to one open database handle.
 *
 * Passed to use cases as a plain dependency rather than imported by them
 * (`conventions.md` §2), which is what lets a test hand over its own database
 * with no module mocking.
 */
export function createTransactor(sqlite: SqliteDatabase): Transactor {
  const qb = createKysely(sqlite)

  const tx: Tx = {
    qb,
    all<O>(query: Compilable<O>): O[] {
      const { sql, parameters } = query.compile()
      return sqlite.prepare(sql).all(...(parameters as unknown[])) as O[]
    },
    get<O>(query: Compilable<O>): O | undefined {
      const { sql, parameters } = query.compile()
      return sqlite.prepare(sql).get(...(parameters as unknown[])) as O | undefined
    },
    run(query: Compilable<unknown>): { changes: number } {
      const { sql, parameters } = query.compile()
      const { changes } = sqlite.prepare(sql).run(...(parameters as unknown[]))
      return { changes }
    },
  }

  return {
    read<T>(fn: (tx: Tx) => T): T {
      return fn(tx)
    },
    write<T>(fn: (tx: Tx) => T): T {
      // better-sqlite3 runs this synchronously and rolls back if fn throws.
      // Nested write() calls become SAVEPOINTs, but a command should open one
      // transaction, not several — see conventions.md §3.
      return sqlite.transaction(fn)(tx)
    },
  }
}
