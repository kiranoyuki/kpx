import { describe, expect, it } from 'vitest'

import { FixedClock, SystemClock } from './clock.js'
import { SeqIds, UuidIds } from './ids.js'
import { clinicDateOf, clinicTimeOf, instantOfSlot, toLocalDate, toLocalTime } from './time.js'

describe('FixedClock', () => {
  it('reads back exactly the moment it was given', () => {
    expect(FixedClock('2026-09-04T10:00:00Z').now()).toBe('2026-09-04T10:00:00.000Z')
  })

  it('does not move on its own', () => {
    const clock = FixedClock('2026-09-04T10:00:00Z')
    const first = clock.now()
    for (let i = 0; i < 100_000; i++) void i
    expect(clock.now()).toBe(first)
  })

  it('moves only when asked', () => {
    const clock = FixedClock('2026-09-04T10:00:00Z')
    clock.advance(24 * 60 * 60 * 1000)
    expect(clock.now()).toBe('2026-09-05T10:00:00.000Z')
  })

  it('is what makes a "within 24 hours" rule assertable', () => {
    const clock = FixedClock('2026-09-04T10:00:00Z')
    const startsAt = instantOfSlot(toLocalDate('2026-09-05'), toLocalTime('09:00'))
    const hoursAway = (new Date(startsAt).getTime() - new Date(clock.now()).getTime()) / 3_600_000

    expect(hoursAway).toBeLessThan(24)
    expect(hoursAway).toBeGreaterThan(0)
  })

  it('lands in the clinic day the test expects', () => {
    const clock = FixedClock('2026-09-04T10:00:00Z')
    expect(clinicDateOf(clock.now())).toBe('2026-09-04')
    expect(clinicTimeOf(clock.now())).toBe('17:00')
  })

  it('refuses a naive string, which has no moment', () => {
    expect(() => FixedClock('2026-09-04 10:00:00')).toThrow()
  })
})

describe('SystemClock', () => {
  it('returns a well-formed Instant', () => {
    expect(SystemClock.now()).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/)
  })
})

describe('SeqIds', () => {
  it('counts from one, so a test can name the row it expects', () => {
    const ids = SeqIds('app')
    expect([ids.next(), ids.next(), ids.next()]).toEqual(['app-1', 'app-2', 'app-3'])
  })

  it('keeps separate sequences separate', () => {
    const a = SeqIds('app')
    const b = SeqIds('usr')
    a.next()
    expect(b.next()).toBe('usr-1')
  })
})

describe('UuidIds', () => {
  it('gives a fresh uuid each time', () => {
    const first = UuidIds.next()
    expect(first).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    expect(UuidIds.next()).not.toBe(first)
  })
})
