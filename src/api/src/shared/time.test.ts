import { describe, expect, it } from 'vitest'

import {
  addDays, addMinutes, CLINIC_TIME_ZONE, clinicDateOf, clinicTimeOf, clinicTimeOfSecond,
  compare, daysBetween, instantOfSlot, isAfter, isBefore, slotOfInstant,
  toInstant, toLocalDate, toLocalTime, weekdayOf,
} from './time.js'

describe('the clinic timezone', () => {
  it('is an IANA name, not an offset', () => {
    expect(CLINIC_TIME_ZONE).toBe('Asia/Ho_Chi_Minh')
  })

  it('is +7 all year — the test that would announce a change of law', () => {
    for (const month of ['01', '04', '07', '10']) {
      const slot = instantOfSlot(toLocalDate(`2026-${month}-15`), toLocalTime('10:00'))
      expect(slot).toBe(`2026-${month}-15T03:00:00.000Z`)
    }
  })
})

describe('a scheduling slot is business time', () => {
  it('is stored as written and never converted', () => {
    // The appointment is 10:00 at the clinic. That is the fact; nothing about
    // the patient's location changes it.
    expect(toLocalDate('2026-09-10')).toBe('2026-09-10')
    expect(toLocalTime('10:00')).toBe('10:00')
  })

  it('derives an absolute instant when one is genuinely needed', () => {
    expect(instantOfSlot(toLocalDate('2026-09-10'), toLocalTime('10:00'))).toBe(
      '2026-09-10T03:00:00.000Z',
    )
  })

  it('round-trips back to the same slot', () => {
    for (const time of ['00:00', '08:30', '10:00', '17:00', '23:59']) {
      const date = toLocalDate('2026-09-10')
      const back = slotOfInstant(instantOfSlot(date, toLocalTime(time)))
      expect(back).toEqual({ date: '2026-09-10', time })
    }
  })

  it('crosses the UTC day boundary without losing the clinic day', () => {
    // 00:00 clinic on the 10th is 17:00 UTC on the 9th.
    expect(instantOfSlot(toLocalDate('2026-09-10'), toLocalTime('00:00'))).toBe(
      '2026-09-09T17:00:00.000Z',
    )
    expect(clinicDateOf(toInstant('2026-09-09T17:00:00.000Z'))).toBe('2026-09-10')
  })

  it('reads the same to a patient abroad, because the API states the zone', () => {
    // The New York patient is shown "10:00 Vietnam time". The instant behind it
    // is one moment; their evening, the clinic's morning.
    const instant = instantOfSlot(toLocalDate('2026-09-10'), toLocalTime('10:00'))
    const inNewYork = new Date(instant).toLocaleString('en-GB', {
      timeZone: 'America/New_York',
      day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false,
    })
    expect(inNewYork).toBe('09/09, 23:00')
    expect(clinicTimeOf(instant)).toBe('10:00')
  })
})

describe('an event is an absolute instant', () => {
  it('accepts UTC', () => {
    expect(toInstant('2026-09-10T03:30:00.000Z')).toBe('2026-09-10T03:30:00.000Z')
    expect(toInstant('2026-09-10T03:30:00Z')).toBe('2026-09-10T03:30:00Z')
  })

  it('refuses an offset-bearing string rather than normalising it', () => {
    // If one arrives, some layer is passing along a client's idea of the time.
    expect(() => toInstant('2026-09-10T10:00:00+07:00')).toThrow()
  })

  it('refuses a naive datetime, which has no moment', () => {
    expect(() => toInstant('2026-09-10 10:00:00')).toThrow()
  })

  it('renders in clinic time for staff to read', () => {
    // The New York patient pressed Book at 23:30 their time on the 9th.
    const pressedBook = toInstant('2026-09-10T03:30:00.000Z')
    expect(clinicDateOf(pressedBook)).toBe('2026-09-10')
    expect(clinicTimeOf(pressedBook)).toBe('10:30')
    expect(clinicTimeOfSecond(pressedBook)).toBe('10:30:00')
  })

  it('orders correctly across clients in different zones', () => {
    // Sydney 13:29 and New York 23:30 on the 9th: Sydney is earlier.
    const fromSydney = toInstant('2026-09-10T03:29:00.000Z')
    const fromNewYork = toInstant('2026-09-10T03:30:00.000Z')
    expect(isBefore(fromSydney, fromNewYork)).toBe(true)
  })
})

describe('calendar arithmetic', () => {
  const cases: [string, number, string][] = [
    ['2026-09-10', 1, '2026-09-11'],
    ['2026-08-31', 1, '2026-09-01'],
    ['2026-12-31', 1, '2027-01-01'],
    ['2026-01-01', -1, '2025-12-31'],
    ['2024-02-28', 1, '2024-02-29'],
    ['2026-02-28', 1, '2026-03-01'],
    ['2026-09-10', 0, '2026-09-10'],
  ]

  it.each(cases)('%s + %d days → %s', (from, days, expected) => {
    expect(addDays(toLocalDate(from), days)).toBe(expected)
  })

  it('never drifts across a whole year', () => {
    let date = toLocalDate('2026-01-01')
    for (let i = 0; i < 365; i++) date = addDays(date, 1)
    expect(date).toBe('2027-01-01')
  })

  it('counts whole days between dates', () => {
    expect(daysBetween(toLocalDate('2026-09-10'), toLocalDate('2026-09-17'))).toBe(7)
    expect(daysBetween(toLocalDate('2026-09-17'), toLocalDate('2026-09-10'))).toBe(-7)
  })

  it('gives Sunday as 0, matching doctor_schedule.day_of_week', () => {
    expect(weekdayOf(toLocalDate('2026-09-13'))).toBe(0)
    expect(weekdayOf(toLocalDate('2026-09-14'))).toBe(1)
  })

  it('adds minutes to a slot, for the end of an appointment', () => {
    expect(addMinutes(toLocalTime('10:00'), 30)).toBe('10:30')
    expect(addMinutes(toLocalTime('09:45'), 30)).toBe('10:15')
    expect(addMinutes(toLocalTime('10:00'), -30)).toBe('09:30')
  })

  it('refuses to run a slot past midnight rather than wrapping silently', () => {
    expect(() => addMinutes(toLocalTime('23:45'), 30)).toThrow(/leaves the day/)
  })
})

describe('ordering', () => {
  it('is lexicographic, because every format is fixed width', () => {
    expect(isBefore('2026-09-10', '2026-09-11')).toBe(true)
    expect(isAfter('10:00', '08:30')).toBe(true)
    expect(compare('10:00', '10:00')).toBe(0)
  })
})

describe('the constructors refuse the wrong shape', () => {
  const bad: [string, () => unknown][] = [
    ['a naive datetime as an Instant', () => toInstant('2026-09-10 10:00:00')],
    ['a date as an Instant', () => toInstant('2026-09-10')],
    ['a datetime as a LocalDate', () => toLocalDate('2026-09-10 10:00:00')],
    ['a 25th hour', () => toLocalTime('25:00')],
    ['a 61st minute', () => toLocalTime('10:61')],
    ['a made-up shape', () => toLocalDate('10/09/2026')],
  ]

  it.each(bad)('rejects %s', (_why, attempt) => {
    expect(attempt).toThrow()
  })
})
