/**
 * Time. Four types that look alike and mean different things.
 *
 * `conventions.md` §4: conflating them is the most likely time bug in this
 * system, and every one of them is a string, so only the type system can keep
 * them apart. They are branded for that reason — the compiler refuses a
 * `LocalDate` where an `Instant` belongs.
 *
 * | Type             | Example                     | Stored as | Converted? |
 * |------------------|-----------------------------|-----------|------------|
 * | `Instant`        | `2026-08-20T10:00:00+07:00` | never     | it *is* the conversion |
 * | `ClinicDateTime` | `2026-08-20 10:00:00`       | yes       | to/from Instant only |
 * | `LocalDate`      | `2026-08-20`                | yes       | **never** |
 * | `LocalTime`      | `10:00`                     | yes       | **never** |
 *
 * ## Why the database holds clinic-local text
 *
 * Every timestamp in `db/kpx.db` is naive clinic wall time, and 34 `date()` /
 * `time()` expressions across the views read it that way. SQLite converts any
 * offset-bearing timestamp to UTC, so storing `…T10:00:00+07:00` would make
 * `time()` report `03:00:00` and put every late appointment on the wrong day
 * sheet. Storage stays naive; the offset lives at the edges.
 *
 * Vietnam is UTC+7 all year and has never observed DST, so naive local text is
 * unambiguous and the instant is always recoverable. `time.test.ts` checks that
 * against `Intl` in January and July — if Vietnam ever adopts DST, that test
 * fails rather than the arithmetic silently drifting.
 *
 * ## Why the API speaks Instants
 *
 * A naive `2026-08-20 10:00:00` crossing the HTTP boundary is the one string a
 * client abroad can misread as its own local time. Everything leaving the API
 * carries the offset, which is simultaneously a true moment and readable as
 * clinic time.
 *
 * ## Where "now" comes from
 *
 * `Clock.now()`, always — never `new Date()`, never `datetime('now')` (which is
 * UTC), never `'localtime'` (which is the *server's* zone). The API stamps every
 * audit field itself, so a request from anywhere is logged in clinic time. It
 * never accepts a client-supplied timestamp for an audit field: a client may say
 * which slot it wants, never when something happened.
 */

declare const brand: unique symbol

/** An exact moment, carrying its offset. What the API emits and accepts. */
export type Instant = string & { readonly [brand]: 'Instant' }
/** The stored form: clinic wall time, no offset. What every timestamp column holds. */
export type ClinicDateTime = string & { readonly [brand]: 'ClinicDateTime' }
/** A calendar day. A pay period runs between these. Never converted. */
export type LocalDate = string & { readonly [brand]: 'LocalDate' }
/** A time of day. Opening hours are these. Never converted. */
export type LocalTime = string & { readonly [brand]: 'LocalTime' }

/** The clinic's business timezone. Never the server's, which is not knowable. */
export const CLINIC_TIME_ZONE = 'Asia/Ho_Chi_Minh'

/** Constant because Vietnam has no DST. `time.test.ts` fails if that changes. */
export const CLINIC_UTC_OFFSET = '+07:00'

const INSTANT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/
const CLINIC_DATE_TIME = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/
const LOCAL_DATE = /^\d{4}-\d{2}-\d{2}$/
const LOCAL_TIME = /^\d{2}:\d{2}(?::\d{2})?$/

function reject(what: string, value: string, shape: string): never {
  throw new RangeError(`${value} is not a ${what} (expected ${shape})`)
}

export function toInstant(value: string): Instant {
  if (!INSTANT.test(value)) reject('Instant', value, '2026-08-20T10:00:00+07:00')
  return value as Instant
}

export function toClinicDateTime(value: string): ClinicDateTime {
  if (!CLINIC_DATE_TIME.test(value)) reject('ClinicDateTime', value, '2026-08-20 10:00:00')
  return value as ClinicDateTime
}

export function toLocalDate(value: string): LocalDate {
  if (!LOCAL_DATE.test(value)) reject('LocalDate', value, '2026-08-20')
  return value as LocalDate
}

export function toLocalTime(value: string): LocalTime {
  if (!LOCAL_TIME.test(value)) reject('LocalTime', value, '10:00')
  return value as LocalTime
}

/**
 * The clinic's wall-clock fields for a moment.
 *
 * Uses `Intl` rather than adding seven hours, so the answer stays right if
 * Vietnam's offset ever changes. `Date` appears here and nowhere else outside
 * `clock.ts`; that is what the lint rule permits and why this function exists.
 */
const CLINIC_PARTS = new Intl.DateTimeFormat('en-CA', {
  timeZone: CLINIC_TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hour12: false,
})

function clinicParts(instant: Instant): { date: string; time: string } {
  const parts = CLINIC_PARTS.formatToParts(new Date(instant))
  const get = (type: string): string => parts.find((p) => p.type === type)?.value ?? '00'
  // en-CA yields ISO-shaped parts; hourCycle can render midnight as 24.
  const hour = get('hour') === '24' ? '00' : get('hour')
  return {
    date: `${get('year')}-${get('month')}-${get('day')}`,
    time: `${hour}:${get('minute')}:${get('second')}`,
  }
}

/** An Instant → the naive clinic text a timestamp column holds. */
export function toStored(instant: Instant): ClinicDateTime {
  const { date, time } = clinicParts(instant)
  return `${date} ${time}` as ClinicDateTime
}

/** A stored timestamp → the Instant the API emits. */
export function fromStored(stored: ClinicDateTime): Instant {
  return `${stored.replace(' ', 'T')}${CLINIC_UTC_OFFSET}` as Instant
}

/** Which clinic day a moment falls on. "Today" is this, from `clock.now()`. */
export function clinicDateOf(instant: Instant): LocalDate {
  return clinicParts(instant).date as LocalDate
}

/** The clinic wall time of a moment, to the minute. */
export function clinicTimeOf(instant: Instant): LocalTime {
  return clinicParts(instant).time.slice(0, 5) as LocalTime
}

/** The calendar day of a stored timestamp, without going near a `Date`. */
export function dateOfStored(stored: ClinicDateTime): LocalDate {
  return stored.slice(0, 10) as LocalDate
}

/** The wall time of a stored timestamp, to the minute. */
export function timeOfStored(stored: ClinicDateTime): LocalTime {
  return stored.slice(11, 16) as LocalTime
}

/** Combines a clinic day and time into the stored form. */
export function storedFrom(date: LocalDate, time: LocalTime): ClinicDateTime {
  const seconds = time.length === 5 ? `${time}:00` : time
  return `${date} ${seconds}` as ClinicDateTime
}

/**
 * Calendar arithmetic on a day, via `Date.UTC` — a calendar, not a clock. The
 * hazard §4 names is `new Date('2026-08-20')` followed by reading *local*
 * fields; every part of this stays in UTC, so no zone can shift the answer.
 */
export function addDays(date: LocalDate, days: number): LocalDate {
  if (!Number.isInteger(days)) throw new RangeError(`days must be whole, got ${String(days)}`)
  const [y, m, d] = date.split('-').map(Number) as [number, number, number]
  const shifted = new Date(Date.UTC(y, m - 1, d + days))
  return shifted.toISOString().slice(0, 10) as LocalDate
}

/** 0 = Sunday, matching `doctor_schedule.day_of_week`. */
export function weekdayOf(date: LocalDate): number {
  const [y, m, d] = date.split('-').map(Number) as [number, number, number]
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay()
}

/** Whole days from `from` to `to`; negative if `to` is earlier. */
export function daysBetween(from: LocalDate, to: LocalDate): number {
  const at = (date: LocalDate): number => {
    const [y, m, d] = date.split('-').map(Number) as [number, number, number]
    return Date.UTC(y, m - 1, d)
  }
  return Math.round((at(to) - at(from)) / 86_400_000)
}

/**
 * All four formats are fixed-width and zero-padded, so lexicographic order is
 * chronological order. No parsing, and no `Date`.
 */
export function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}

export const isBefore = (a: string, b: string): boolean => compare(a, b) < 0
export const isAfter = (a: string, b: string): boolean => compare(a, b) > 0
