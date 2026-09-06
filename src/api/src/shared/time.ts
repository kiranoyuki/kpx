/**
 * Time. Two kinds of it, and they are not interchangeable.
 *
 * ## The policy (`conventions.md` §4)
 *
 * **Scheduling is clinic business time. Events are absolute instants.**
 *
 * | Kind | Type | Example | Stored as |
 * |---|---|---|---|
 * | *when the clinic will see you* | `LocalDate` + `LocalTime` | `2026-09-10`, `10:00` | as written, never converted |
 * | *when something happened* | `Instant` | `2026-09-10T03:30:00.000Z` | UTC |
 *
 * An appointment at 10:00 on 10 September is a business fact about the clinic's
 * day. It is 10:00 whether the patient is in Hanoi or New York, and converting
 * it to anyone's local time would change what it means. So it is stored exactly
 * as written and never passes through a timezone.
 *
 * "When did the patient press Book" is the opposite: one moment, observed from
 * wherever the patient was. Stored UTC, so ordering and causality hold across
 * clients in different zones, and rendered in clinic time for staff to read.
 *
 * ## The timezone is a name, not an offset
 *
 * `CLINIC_TIME_ZONE` is the IANA identifier, not `+07:00`. Vietnam has stayed
 * UTC+7 for decades, but the business rule is "the time at the clinic in
 * Vietnam", not "seven hours ahead" — and the name survives a change of law
 * while the offset silently would not. Conversion goes through `Intl`, so the
 * offset is looked up rather than assumed.
 *
 * ## Where "now" comes from
 *
 * `Clock.now()`, always. Never `new Date()` in business logic, never
 * `datetime('now','localtime')` (the *server's* zone), and never a timestamp
 * the client sent. A client may say which slot it wants — that is intent. When
 * something happened is the server's answer, because a browser's clock can be
 * wrong, stale, or lying.
 */

declare const brand: unique symbol

/** An exact moment, UTC. What every event and audit column stores. */
export type Instant = string & { readonly [brand]: 'Instant' }
/** A calendar day in clinic business time. Never converted. */
export type LocalDate = string & { readonly [brand]: 'LocalDate' }
/** A time of day in clinic business time. Never converted. */
export type LocalTime = string & { readonly [brand]: 'LocalTime' }

/** IANA name, deliberately — see the header. */
export const CLINIC_TIME_ZONE = 'Asia/Ho_Chi_Minh'

const INSTANT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/
const LOCAL_DATE = /^\d{4}-\d{2}-\d{2}$/
const LOCAL_TIME = /^([01]\d|2[0-3]):[0-5]\d$/

function reject(what: string, value: string, shape: string): never {
  throw new RangeError(`${value} is not a ${what} (expected ${shape})`)
}

/**
 * Accepts UTC only. An offset-bearing string is refused rather than converted:
 * if one reaches here, some layer is passing along a client's idea of the time,
 * and silently normalising it would hide that.
 */
export function toInstant(value: string): Instant {
  if (!INSTANT.test(value)) reject('Instant', value, '2026-09-10T03:30:00.000Z (UTC)')
  return value as Instant
}

export function toLocalDate(value: string): LocalDate {
  if (!LOCAL_DATE.test(value)) reject('LocalDate', value, '2026-09-10')
  return value as LocalDate
}

export function toLocalTime(value: string): LocalTime {
  if (!LOCAL_TIME.test(value)) reject('LocalTime', value, '10:00')
  return value as LocalTime
}

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

function partsOf(instant: Instant): Record<string, string> {
  const found: Record<string, string> = {}
  for (const part of CLINIC_PARTS.formatToParts(new Date(instant))) {
    found[part.type] = part.value
  }
  // hourCycle can render clinic midnight as 24.
  if (found.hour === '24') found.hour = '00'
  return found
}

/** Which clinic day a moment fell on. "Today" is this, from `clock.now()`. */
export function clinicDateOf(instant: Instant): LocalDate {
  const p = partsOf(instant)
  return `${p.year ?? ''}-${p.month ?? ''}-${p.day ?? ''}` as LocalDate
}

/** The clinic wall time a moment fell at — for showing staff when something happened. */
export function clinicTimeOf(instant: Instant): LocalTime {
  const p = partsOf(instant)
  return `${p.hour ?? ''}:${p.minute ?? ''}` as LocalTime
}

/** The clinic wall time to the second, for an audit line. */
export function clinicTimeOfSecond(instant: Instant): string {
  const p = partsOf(instant)
  return `${p.hour ?? ''}:${p.minute ?? ''}:${p.second ?? ''}`
}

/**
 * The offset the clinic was on at a given moment, in minutes.
 *
 * Looked up through `Intl` rather than hard-coded, so this stays correct if
 * Vietnam's offset ever changes. `time.test.ts` asserts it is +7h across the
 * year, and that test is what would announce such a change.
 */
function clinicOffsetMinutesAt(utcMillis: number): number {
  const p = partsOf(new Date(utcMillis).toISOString() as Instant)
  const asIfUtc = Date.UTC(
    Number(p.year),
    Number(p.month) - 1,
    Number(p.day),
    Number(p.hour),
    Number(p.minute),
    Number(p.second),
  )
  return (asIfUtc - utcMillis) / 60_000
}

/**
 * A clinic appointment slot → the absolute moment it starts.
 *
 * **Derived, never the source of truth.** The business fact is the date and the
 * time; this is for the things that need a real instant — reminder scheduling,
 * background jobs, calendar exports, ordering across clinics.
 *
 * Resolved in two passes because an offset lookup needs a moment to look up,
 * and the moment is what is being computed. The second pass settles it. In a
 * zone with DST the first guess can land on the wrong side of a transition;
 * Vietnam has none, so the passes agree, and the loop costs nothing.
 */
export function instantOfSlot(date: LocalDate, time: LocalTime): Instant {
  const [y, m, d] = date.split('-').map(Number) as [number, number, number]
  const [hh, mm] = time.split(':').map(Number) as [number, number]
  const wall = Date.UTC(y, m - 1, d, hh, mm)

  let utc = wall - clinicOffsetMinutesAt(wall) * 60_000
  utc = wall - clinicOffsetMinutesAt(utc) * 60_000

  return new Date(utc).toISOString() as Instant
}

/** The clinic slot a moment corresponds to — the inverse of `instantOfSlot`. */
export function slotOfInstant(instant: Instant): { date: LocalDate; time: LocalTime } {
  return { date: clinicDateOf(instant), time: clinicTimeOf(instant) }
}

/**
 * Calendar arithmetic on a business day, via `Date.UTC` — a calendar, not a
 * clock. The hazard §4 names is `new Date('2026-09-10')` followed by reading a
 * *local* field; everything here stays in UTC, so no zone can shift the answer.
 */
export function addDays(date: LocalDate, days: number): LocalDate {
  if (!Number.isInteger(days)) throw new RangeError(`days must be whole, got ${String(days)}`)
  const [y, m, d] = date.split('-').map(Number) as [number, number, number]
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10) as LocalDate
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

/** Minutes added to a slot time, staying inside the day. */
export function addMinutes(time: LocalTime, minutes: number): LocalTime {
  const [hh, mm] = time.split(':').map(Number) as [number, number]
  const total = hh * 60 + mm + minutes
  if (total < 0 || total >= 24 * 60) {
    throw new RangeError(`${time} + ${String(minutes)} minutes leaves the day`)
  }
  const pad = (n: number): string => String(n).padStart(2, '0')
  return `${pad(Math.floor(total / 60))}:${pad(total % 60)}` as LocalTime
}

/**
 * Every format here is fixed-width and zero-padded, so lexicographic order is
 * chronological order. No parsing, and no `Date`.
 */
export function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}

export const isBefore = (a: string, b: string): boolean => compare(a, b) < 0
export const isAfter = (a: string, b: string): boolean => compare(a, b) > 0
