/**
 * SQLite constraint violations → `AppError`.
 *
 * The 319 declarative constraints stayed in the schema when the 56 triggers were
 * removed (`api-plan.md` §1). They are real enforcement, and they fire as
 * exceptions from `better-sqlite3` rather than as decisions the application
 * made. Without translation each one is an unhandled throw and therefore a 500,
 * which tells the client nothing and hides a refusal it could have acted on.
 *
 * ## What SQLite actually reports
 *
 * Measured against `db/kpx.db`, not assumed:
 *
 * | code                          | message                                                    |
 * |-------------------------------|------------------------------------------------------------|
 * | `SQLITE_CONSTRAINT_CHECK`     | `CHECK constraint failed: ck_appt_selfbooked_is_online`     |
 * | `SQLITE_CONSTRAINT_CHECK`     | `CHECK constraint failed: status IN ('Provisional', …)`     |
 * | `SQLITE_CONSTRAINT_FOREIGNKEY`| `FOREIGN KEY constraint failed`                             |
 * | `SQLITE_CONSTRAINT_UNIQUE`    | `UNIQUE constraint failed: app_user.national_id`            |
 * | `SQLITE_CONSTRAINT_NOTNULL`   | `NOT NULL constraint failed: app_user.full_name`            |
 *
 * **The two CHECK rows are the thing to understand.** 65 of the schema's
 * constraints are named `ck_*` and report that name; the other 111 are inline
 * and report *their own SQL expression*. A name is a stable identifier worth
 * mapping to a code. An expression is not: it changes whenever anyone edits the
 * predicate, and it is schema internals that must never reach a client. So a
 * named constraint gets a specific code and an unnamed one gets a generic
 * refusal — never a code derived from the text.
 *
 * ## No SQLite text ever reaches the response
 *
 * Every branch returns a code and no message, so the wording comes from the
 * catalogue (step 5c) rather than from SQLite. The original error is attached as
 * `cause` for the log and goes no further.
 */

import { AppError } from './AppError.js'

/** An unnamed inline CHECK: refused, but there is no stable name to report. */
export const CONSTRAINT_VIOLATED = 'CONSTRAINT_VIOLATED'
/** A foreign key pointed at a row that does not exist. */
export const REFERENCED_ROW_MISSING = 'REFERENCED_ROW_MISSING'
/** A UNIQUE or PRIMARY KEY collision. */
export const DUPLICATE_VALUE = 'DUPLICATE_VALUE'
/** A NOT NULL column was left empty. */
export const REQUIRED_FIELD_MISSING = 'REQUIRED_FIELD_MISSING'

/**
 * `ck_*` constraint name → catalogue code. Supplied by
 * `shared/errors/constraint-map.ts` in step 5c; until then a named constraint
 * falls back to its own name, upper-cased, which is stable and greppable.
 */
export type ConstraintMap = Readonly<Record<string, string>>

interface SqliteError extends Error {
  code: string
}

function isSqliteError(error: unknown): error is SqliteError {
  return (
    error instanceof Error &&
    'code' in error &&
    typeof (error as SqliteError).code === 'string' &&
    (error as SqliteError).code.startsWith('SQLITE_')
  )
}

/** A named constraint, as opposed to an inline predicate reported verbatim. */
const NAMED_CHECK = /^CHECK constraint failed: (ck_[a-z0-9_]+)$/
const UNIQUE_COLUMNS = /^UNIQUE constraint failed: (.+)$/
const NOT_NULL_COLUMN = /^NOT NULL constraint failed: \w+\.(\w+)$/

/** `national_id` → `nationalId`: the API speaks camelCase, the schema snake. */
function toField(column: string): string {
  return column.replace(/_([a-z0-9])/g, (_, c: string) => c.toUpperCase())
}

/** `app_user.national_id, app_user.phone` → the first column's name. */
function firstColumn(columns: string): string | undefined {
  const first = columns.split(',')[0]?.trim()
  return first?.split('.').pop()
}

/**
 * Returns an `AppError` for a recognised constraint violation, or `undefined`
 * for anything else — a disk error, a syntax error, a genuine bug. Those stay
 * unrecognised on purpose so the handler reports them as 500 with nothing
 * leaked, rather than dressing a fault up as a refusal the client could fix.
 */
export function translateSqliteError(
  error: unknown,
  constraintToCode: ConstraintMap = {},
): AppError | undefined {
  if (!isSqliteError(error)) return undefined

  switch (error.code) {
    case 'SQLITE_CONSTRAINT_CHECK': {
      const name = NAMED_CHECK.exec(error.message)?.[1]
      if (name === undefined) {
        // Unnamed: the message is the SQL predicate itself. Refuse, say no more.
        return new AppError({ code: CONSTRAINT_VIOLATED, status: 422, cause: error })
      }
      return new AppError({
        code: constraintToCode[name] ?? name.toUpperCase(),
        status: 422,
        cause: error,
      })
    }

    case 'SQLITE_CONSTRAINT_FOREIGNKEY':
      // SQLite names neither the key nor the table here, so there is no field
      // to point at — only that something referenced does not exist.
      return new AppError({ code: REFERENCED_ROW_MISSING, status: 422, cause: error })

    case 'SQLITE_CONSTRAINT_UNIQUE':
    case 'SQLITE_CONSTRAINT_PRIMARYKEY': {
      const columns = UNIQUE_COLUMNS.exec(error.message)?.[1]
      const column = columns === undefined ? undefined : firstColumn(columns)
      // 409: valid request, collides with state that already exists.
      return new AppError({
        code: DUPLICATE_VALUE,
        status: 409,
        field: column === undefined ? undefined : toField(column),
        cause: error,
      })
    }

    case 'SQLITE_CONSTRAINT_NOTNULL': {
      const column = NOT_NULL_COLUMN.exec(error.message)?.[1]
      return new AppError({
        code: REQUIRED_FIELD_MISSING,
        status: 422,
        field: column === undefined ? undefined : toField(column),
        cause: error,
      })
    }

    default:
      return undefined
  }
}
