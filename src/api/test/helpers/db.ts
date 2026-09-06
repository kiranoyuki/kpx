/**
 * A fresh database per test file.
 *
 * ## Why a template, and not a rebuild each time
 *
 * Applying the 18 SQL modules takes ~73ms; copying the resulting file takes
 * under a millisecond. So the modules are applied **once per worker process**
 * into a template, and every `createTestDatabase()` copies that file. Twenty
 * test files then cost 73ms rather than a second and a half, and the cost does
 * not grow as the schema does.
 *
 * ## Why the real SQL, and not a fixture
 *
 * The templates are built from `db/modules/*.sql` — the same files `db/build.sh`
 * runs and the same ones that produce production's schema. A hand-written
 * fixture would drift, and would quietly stop testing the 319 constraints and 37
 * views that are the point.
 *
 * ## Isolation
 *
 * Each database is its own file in its own temp directory, so two test files can
 * insert the same primary key and neither sees the other. `isolation-a.test.ts`
 * and `isolation-b.test.ts` do exactly that, on purpose.
 */

import { createHash } from 'node:crypto'
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import {
  createTransactor,
  openDatabase,
  Sqlite,
  type SqliteDatabase,
  type Transactor,
} from '@kpx/db'

const MODULES_DIR = join(import.meta.dirname, '../../../../db/modules')

export interface TestDatabase {
  sqlite: SqliteDatabase
  tx: Transactor
  /** The file on disk, for the rare test that needs a second connection. */
  path: string
  /** Closes the handle and removes the temp directory. */
  close: () => void
}

export interface TestDatabaseOptions {
  /**
   * Include the `*_seed.sql` rows. Default true — the clinic's example people,
   * chairs and services, including the awkward ones (a departed doctor who is
   * still a patient, a superseded price, a declined procedure).
   *
   * Pass false for a schema-only database when a test needs to control every row.
   */
  seed?: boolean
}

function sqlFiles(includeSeed: boolean): string[] {
  return readdirSync(MODULES_DIR)
    .filter((f) => f.endsWith('.sql'))
    .filter((f) => includeSeed || f.includes('_schema'))
    .sort()
}

/**
 * Templates live in one directory, named by a hash of the SQL that produced
 * them, and are **reused across runs**. Two consequences worth having:
 *
 * - a second `npm test` skips the 73ms rebuild entirely
 * - editing any module changes the hash, so a stale template can never be used
 *
 * They are deliberately not deleted on exit. An exit hook does not fire
 * reliably when a test runner tears its workers down — which is how 28 stray
 * directories accumulated before this was a hash — and a fixed path cannot
 * accumulate in the first place. Older hashes are pruned when a new one is built.
 */
const TEMPLATE_DIR = join(tmpdir(), 'kpx-templates')

/**
 * Hashes **every** module, not just the ones a given template applies. The two
 * templates then share one prefix and differ only in suffix, so pruning older
 * hashes cannot delete the sibling that a parallel worker is mid-copy of — which
 * is exactly what it did when each hashed only its own subset.
 */
function schemaHash(): string {
  const hash = createHash('sha1')
  for (const file of sqlFiles(true)) {
    hash.update(file)
    hash.update(readFileSync(join(MODULES_DIR, file)))
  }
  return hash.digest('hex').slice(0, 12)
}

function templateFor(includeSeed: boolean): string {
  const files = sqlFiles(includeSeed)
  const key = includeSeed ? 'seeded' : 'schema'
  const hash = schemaHash()
  const path = join(TEMPLATE_DIR, `${hash}-${key}.db`)

  if (existsSync(path)) return path

  mkdirSync(TEMPLATE_DIR, { recursive: true })
  // Built under a private name and renamed into place, so two workers racing
  // cannot leave a half-applied schema behind for the loser to copy.
  const building = `${path}.${String(process.pid)}.tmp`
  const sqlite = new Sqlite(building)
  try {
    for (const file of files) {
      sqlite.exec(readFileSync(join(MODULES_DIR, file), 'utf8'))
    }
  } finally {
    sqlite.close()
  }
  renameSync(building, path)

  // The schema changed, so anything under an older hash is dead weight. Both
  // templates share this prefix, so neither prunes the other.
  for (const stale of readdirSync(TEMPLATE_DIR)) {
    if (!stale.startsWith(hash)) rmSync(join(TEMPLATE_DIR, stale), { force: true })
  }
  return path
}

/**
 * A database of this test's own. Call `close()` in `afterEach` — or `afterAll`
 * if the whole file shares one.
 */
export function createTestDatabase(options: TestDatabaseOptions = {}): TestDatabase {
  const dir = mkdtempSync(join(tmpdir(), 'kpx-test-'))
  const path = join(dir, 'test.db')
  copyFileSync(templateFor(options.seed ?? true), path)

  // Through openDatabase, so tests run under the same pragmas production does —
  // foreign keys on above all. A test that passes with them off proves nothing.
  const sqlite = openDatabase(path)

  return {
    sqlite,
    tx: createTransactor(sqlite),
    path,
    close: () => {
      sqlite.close()
      rmSync(dir, { recursive: true, force: true })
    },
  }
}
