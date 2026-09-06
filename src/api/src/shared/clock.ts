/**
 * The only place the current time enters the system.
 *
 * `conventions.md` §4: business logic never reaches for the time, it receives
 * it. Without that, a rule like "cancellation is inside the 24-hour window" can
 * only be tested by computing the expected answer the same way the code does,
 * which tests nothing. With it:
 *
 * ```
 * Given now          = 2026-09-04 10:00
 * And appointment at = 2026-09-05 09:00
 * Then cancellation is inside the 24-hour window
 * ```
 *
 * This is the one module allowed to call `new Date()`; ESLint bans it
 * everywhere else under `shared/` and `modules/`.
 */

import { toInstant, type Instant } from './time.js'

export interface Clock {
  /** The current moment, carrying its offset. Never a naive string. */
  now: () => Instant
}

/** Production. Reads the machine clock, which is UTC on any sane server. */
export const SystemClock: Clock = {
  now: () => toInstant(new Date().toISOString()),
}

/**
 * Tests. Frozen unless asked to move, so an assertion can name an exact time
 * rather than recomputing one.
 */
export function FixedClock(iso: string): Clock & { advance: (ms: number) => void } {
  let at = new Date(toInstant(iso))
  return {
    now: () => toInstant(at.toISOString()),
    /** Moves the clock, for the rare test that needs two different "now"s. */
    advance: (ms: number) => {
      at = new Date(at.getTime() + ms)
    },
  }
}
