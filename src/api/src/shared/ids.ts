/**
 * The only place a new identifier comes from.
 *
 * `conventions.md` §4, the same argument as the clock: a test asserting that a
 * created row exists cannot name it if the id is random.
 */

import { randomUUID } from 'node:crypto'

export interface Ids {
  next: () => string
}

/** Production. */
export const UuidIds: Ids = {
  next: () => randomUUID(),
}

/**
 * Tests. `SeqIds('app')` yields `app-1`, `app-2`, … so an assertion can name
 * the row it expects.
 */
export function SeqIds(prefix: string): Ids {
  let n = 0
  return {
    next: () => {
      n += 1
      return `${prefix}-${String(n)}`
    },
  }
}
