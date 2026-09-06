/**
 * Half of step 7's Verify. This file and `isolation-b.test.ts` insert the **same**
 * primary key into the same table. Both pass only because each got its own
 * database file; sharing one would make whichever ran second fail on the
 * UNIQUE constraint.
 */

import { afterEach, beforeEach, expect, it } from 'vitest'

import { createTestDatabase, type TestDatabase } from './helpers/db.js'

let db: TestDatabase

beforeEach(() => {
  db = createTestDatabase()
})

afterEach(() => {
  db.close()
})

it('inserts the contested id and sees only its own', () => {
  db.sqlite
    .prepare(
      `INSERT INTO app_user (id, full_name, phone, role, status)
       VALUES ('contested-id', 'From file a', '0900000001', 'Patient', 'Provisional')`,
    )
    .run()

  const row = db.sqlite
    .prepare("SELECT full_name FROM app_user WHERE id = 'contested-id'")
    .get() as { full_name: string }

  expect(row.full_name).toBe('From file a')
})
