/**
 * `@kpx/db` — the database layer, and the only package that knows SQLite is
 * underneath.
 *
 * ## The single-writer rule travels with this package
 *
 * `conventions.md` §3: **exactly one application process may write to
 * kpx.db.** Every check-then-write invariant in the system — chair and doctor
 * overlap, FEFO, stock levels, overlapping shifts and pay periods — rests on
 * it, and a second writer breaks all of them without a single test failing.
 *
 * That this package is importable by anything does **not** make the database
 * safe to open from anything. A second consumer may open it **read-only**. A
 * second *writer* requires revisiting the transaction strategy first, per §3.
 *
 * ## Why the driver is re-exported
 *
 * Consumers get `Kysely` and friends from here rather than installing `kysely`
 * themselves. These are independent npm packages with no shared lockfile, so a
 * consumer with its own copy would produce two `Kysely` classes and two sets of
 * declarations for the same names. Owning the dependency in one place keeps a
 * single copy, and keeps the choice of driver a detail of this package.
 */

export {
  applyPragmas,
  createKysely,
  openDatabase,
  readPragmas,
  type PragmaReport,
  type SqliteDatabase,
} from './connection.js'

export {
  createTransactor,
  type Transactor,
  type Tx,
} from './tx.js'

export type { DB } from './schema.js'

/**
 * The raw better-sqlite3 constructor, for the few callers that must *create* a
 * database rather than open an existing one — test harnesses and tooling.
 * Application code wants `openDatabase`, which applies the pragmas and refuses
 * a path that does not exist.
 */
export { default as Sqlite } from 'better-sqlite3'

// The query-building surface consumers need. Deliberately a short list rather
// than `export *`: each addition is a decision about what the layer above may
// reach for.
export {
  Kysely,
  Transaction,
  sql,
  type Insertable,
  type Selectable,
  type Updateable,
} from 'kysely'
