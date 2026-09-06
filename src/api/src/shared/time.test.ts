import { describe, expect, it } from 'vitest'

import {
  addDays, CLINIC_TIME_ZONE, CLINIC_UTC_OFFSET, clinicDateOf, clinicTimeOf, compare,
  dateOfStored, daysBetween, fromStored, isAfter, isBefore, storedFrom, timeOfStored,
  toClinicDateTime, toInstant, toLocalDate, toLocalTime, toStored, weekdayOf,
} from './time.js'

describe('the clinic timezone', () => {
  it('has no DST — the constant offset is only safe because of this', () => {
    // If Vietnam ever adopts DST this fails, rather than the arithmetic
    // silently drifting for half the year.
    const offsetAt = (iso: string): number => {
      const at = new Date(iso)
      const zoned = new Date(at.toLocaleString('en-US', { timeZone: CLINIC_TIME_ZONE }))
      const utc = new Date(at.toLocaleString('en-US', { timeZone: 'UTC' }))
      return (zoned.getTime() - utc.getTime()) / 3_600_000
    }
    for (const month of ['01', '04', '07', '10']) {
      expect(offsetAt(`2026-${month}-15T00:00:00Z`)).toBe(7)
    }
    expect(CLINIC_UTC_OFFSET).toBe('+07:00')
  })
})

describe('storage round trip', () => {
  const cases: [instant: string, stored: string, why: string][] = [
    ['2026-08-20T03:00:00Z', '2026-08-20 10:00:00', 'a morning appointment'],
    ['2026-08-20T10:00:00+07:00', '2026-08-20 10:00:00', 'the same moment, written with its offset'],
    ['2026-08-20T17:00:00Z', '2026-08-21 00:00:00', 'past 17:00 UTC is already tomorrow at the clinic'],
    ['2026-08-19T17:00:01Z', '2026-08-20 00:00:01', 'just after clinic midnight'],
    ['2026-08-20T16:59:59Z', '2026-08-20 23:59:59', 'the last second of the clinic day'],
    ['2026-01-15T04:00:00Z', '2026-01-15 11:00:00', 'January — no DST'],
    ['2026-07-15T04:00:00Z', '2026-07-15 11:00:00', 'July — still no DST'],
  ]

  it.each(cases)('%s → %s (%s)', (instant, stored) => {
    expect(toStored(toInstant(instant))).toBe(stored)
  })

  it('comes back as the same moment', () => {
    for (const [instant] of cases) {
      const round = fromStored(toStored(toInstant(instant)))
      expect(new Date(round).getTime()).toBe(new Date(instant).getTime())
    }
  })

  it('emits an offset, never a naive string — the one a foreign client misreads', () => {
    expect(fromStored(toClinicDateTime('2026-08-20 10:00:00'))).toBe('2026-08-20T10:00:00+07:00')
  })

  it('reads the same moment in Sydney as at the clinic', () => {
    const emitted = fromStored(toClinicDateTime('2026-08-20 10:00:00'))
    const inSydney = new Date(emitted).toLocaleString('en-GB', {
      timeZone: 'Australia/Sydney', hour: '2-digit', minute: '2-digit', hour12: false,
    })
    expect(inSydney).toBe('13:00')
  })
})

describe('reading a moment as clinic wall time', () => {
  it('gives the clinic day, not the UTC day', () => {
    expect(clinicDateOf(toInstant('2026-08-20T17:30:00Z'))).toBe('2026-08-21')
  })

  it('gives the clinic time', () => {
    expect(clinicTimeOf(toInstant('2026-08-20T03:00:00Z'))).toBe('10:00')
  })

  it('renders clinic midnight as 00:00, not 24:00', () => {
    expect(clinicTimeOf(toInstant('2026-08-19T17:00:00Z'))).toBe('00:00')
    expect(clinicDateOf(toInstant('2026-08-19T17:00:00Z'))).toBe('2026-08-20')
  })
})

describe('stored fields', () => {
  it('splits without going near a Date', () => {
    const stored = toClinicDateTime('2026-08-20 14:30:00')
    expect(dateOfStored(stored)).toBe('2026-08-20')
    expect(timeOfStored(stored)).toBe('14:30')
  })

  it('recombines a day and a time', () => {
    expect(storedFrom(toLocalDate('2026-08-20'), toLocalTime('08:30'))).toBe('2026-08-20 08:30:00')
  })
})

describe('calendar arithmetic', () => {
  const cases: [string, number, string][] = [
    ['2026-08-20', 1, '2026-08-21'],
    ['2026-08-31', 1, '2026-09-01'],
    ['2026-12-31', 1, '2027-01-01'],
    ['2026-01-01', -1, '2025-12-31'],
    ['2024-02-28', 1, '2024-02-29'],
    ['2026-02-28', 1, '2026-03-01'],
    ['2026-08-20', 0, '2026-08-20'],
    ['2026-08-20', 30, '2026-09-19'],
  ]

  it.each(cases)('%s + %d days → %s', (from, days, expected) => {
    expect(addDays(toLocalDate(from), days)).toBe(expected)
  })

  it('never shifts a day, at any hour of any day of a year', () => {
    // The §4 hazard: new Date('2026-08-20') is UTC midnight, which is 07:00 the
    // same day at the clinic. Adding a day the naive way drifts.
    let date = toLocalDate('2026-01-01')
    for (let i = 0; i < 365; i++) date = addDays(date, 1)
    expect(date).toBe('2027-01-01')
  })

  it('counts whole days between two dates', () => {
    expect(daysBetween(toLocalDate('2026-08-20'), toLocalDate('2026-08-27'))).toBe(7)
    expect(daysBetween(toLocalDate('2026-08-27'), toLocalDate('2026-08-20'))).toBe(-7)
  })

  it('gives Sunday as 0, matching doctor_schedule.day_of_week', () => {
    expect(weekdayOf(toLocalDate('2026-08-23'))).toBe(0)
    expect(weekdayOf(toLocalDate('2026-08-24'))).toBe(1)
  })
})

describe('ordering', () => {
  it('is lexicographic, because every format is fixed width', () => {
    expect(isBefore('2026-08-20', '2026-08-21')).toBe(true)
    expect(isAfter('10:00', '08:30')).toBe(true)
    expect(compare('2026-08-20 10:00:00', '2026-08-20 10:00:00')).toBe(0)
  })
})

describe('the constructors refuse the wrong shape', () => {
  const bad: [string, () => unknown][] = [
    ['a naive datetime as an Instant', () => toInstant('2026-08-20 10:00:00')],
    ['a date as an Instant', () => toInstant('2026-08-20')],
    ['an Instant as stored text', () => toClinicDateTime('2026-08-20T10:00:00+07:00')],
    ['a datetime as a LocalDate', () => toLocalDate('2026-08-20 10:00:00')],
    ['nonsense as a LocalTime', () => toLocalTime('half past ten')],
    ['a made-up shape', () => toLocalDate('20/08/2026')],
  ]

  it.each(bad)('rejects %s', (_why, attempt) => {
    expect(attempt).toThrow()
  })

  it('accepts both offset forms of an Instant', () => {
    expect(() => toInstant('2026-08-20T03:00:00Z')).not.toThrow()
    expect(() => toInstant('2026-08-20T03:00:00.123Z')).not.toThrow()
    expect(() => toInstant('2026-08-20T10:00:00+07:00')).not.toThrow()
  })
})
