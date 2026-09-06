import { describe, expect, it } from 'vitest'

import {
  add,
  allocate,
  applyBasisPoints,
  applyRatio,
  assertBasisPoints,
  format,
  formatBasisPoints,
  multiply,
  negate,
  subtract,
  sum,
  type Rounding,
} from './money.js'

describe('applyBasisPoints', () => {
  const cases: [amount: number, rate: number, expected: number, why: string][] = [
    [1_000_000, 1500, 150_000, '15% of a round million'],
    [1_000_000, 0, 0, 'a zero rate yields nothing'],
    [1_000_000, 10_000, 1_000_000, '100% is the whole amount'],
    [0, 1500, 0, 'a rate on nothing is nothing'],
    [1_000_000, 750, 75_000, '7.5% — the fractional percent §5 names'],
    [1_000_000, 25, 2_500, '0.25%'],
    [123_456, 800, 9_876, '8% VAT on an unround amount'],
    [5, 1000, 1, '10% of 5 is 0.5, and a tie rounds away from zero'],
    [-5, 1000, -1, 'the same tie on a credit rounds away from zero too'],
    [-1_000_000, 1500, -150_000, 'a credit takes the rate like a charge'],
    [15, 1000, 2, '1.5 rounds up'],
    [14, 1000, 1, '1.4 rounds down'],
  ]

  it.each(cases)('%d at %d bp → %d (%s)', (amount, rate, expected) => {
    expect(applyBasisPoints(amount, rate)).toBe(expected)
  })

  it('rejects a decimal rate, which is a float rate in disguise', () => {
    expect(() => applyBasisPoints(1_000_000, 0.15)).toThrow(/basis points/)
  })

  it('names conventions §5 in the error, so the fix is obvious', () => {
    expect(() => assertBasisPoints(0.15)).toThrow(/§5/)
  })

  it('rejects an amount that is not whole đồng', () => {
    expect(() => applyBasisPoints(100.5, 1000)).toThrow(/whole đồng/)
  })

  const rounding: [number, number, Rounding, number][] = [
    [15, 1000, 'half-away-from-zero', 2],
    [15, 1000, 'toward-zero', 1],
    [-15, 1000, 'half-away-from-zero', -2],
    [-15, 1000, 'toward-zero', -1],
    [29, 1000, 'toward-zero', 2],
  ]

  it.each(rounding)('%d at %d bp under %s → %d', (amount, rate, policy, expected) => {
    expect(applyBasisPoints(amount, rate, policy)).toBe(expected)
  })

  it('never returns negative zero, which would print as "-0 ₫"', () => {
    expect(Object.is(applyBasisPoints(-200_000, 0), 0)).toBe(true)
    expect(Object.is(applyBasisPoints(-4, 1000, 'toward-zero'), 0)).toBe(true)
    expect(format(applyBasisPoints(-200_000, 0))).toBe('0 ₫')
  })

  it('refuses an intermediate too large to be exact, rather than losing đồng', () => {
    expect(() => applyBasisPoints(Number.MAX_SAFE_INTEGER, 10_000)).toThrow(/exact integer range/)
  })
})

describe('allocate', () => {
  const cases: [total: number, weights: number[], expected: number[], why: string][] = [
    [100, [1, 1], [50, 50], 'an even split'],
    [100, [1, 1, 1], [33, 33, 34], 'the remainder lands on the last line'],
    [10, [1, 2, 7], [1, 2, 7], 'proportional and exact'],
    [1, [1, 1, 1], [0, 0, 1], 'a single đồng cannot be split three ways'],
    [-100, [1, 1, 1], [-33, -33, -34], 'a credit allocates the same way'],
    [100, [0, 1], [0, 100], 'a zero weight gets nothing'],
    [100, [1, 0], [100, 0], 'and the remainder skips it'],
    [0, [0, 0], [0, 0], 'nothing across nothing'],
    [7, [3, 0, 4], [3, 0, 4], 'zero weights in the middle are left out'],
  ]

  it.each(cases)('%d across %j → %j (%s)', (total, weights, expected) => {
    expect(allocate(total, weights)).toEqual(expected)
  })

  it('always sums to exactly the amount allocated', () => {
    for (let total = -50; total <= 50; total++) {
      for (const weights of [[1, 1, 1], [1, 2, 3], [5, 1], [7, 7, 7, 7], [1, 0, 2]]) {
        expect(sum(allocate(total, weights))).toBe(total)
      }
    }
  })

  it('returns nothing for no weights', () => {
    expect(allocate(100, [])).toEqual([])
  })

  it('refuses to invent a split when every weight is zero', () => {
    expect(() => allocate(100, [0, 0])).toThrow(/zero total weight/)
  })

  it('rejects a negative weight', () => {
    expect(() => allocate(100, [1, -1])).toThrow(/non-negative/)
  })
})

describe('arithmetic', () => {
  it('adds and sums', () => {
    expect(add(1, 2, 3)).toBe(6)
    expect(sum([1_000_000, -250_000])).toBe(750_000)
  })

  it('subtracts into a credit', () => {
    expect(subtract(100, 250)).toBe(-150)
  })

  it('negates, which is how a correction is recorded (§6)', () => {
    expect(negate(1_000_000)).toBe(-1_000_000)
    expect(negate(-1_000_000)).toBe(1_000_000)
  })

  it('multiplies by a whole quantity', () => {
    expect(multiply(250_000, 3)).toBe(750_000)
  })

  it('refuses a fractional quantity', () => {
    expect(() => multiply(250_000, 1.5)).toThrow(/whole/)
  })

  it('refuses a fractional amount anywhere', () => {
    expect(() => add(1.5, 1)).toThrow(/whole đồng/)
    expect(() => subtract(1.5, 1)).toThrow(/whole đồng/)
  })
})

describe('applyRatio', () => {
  it('takes an explicit two-integer ratio', () => {
    expect(applyRatio(1_000_000, { numerator: 1, denominator: 3 })).toBe(333_333)
  })

  it('refuses a decimal masquerading as a ratio', () => {
    expect(() => applyRatio(100, { numerator: 0.5, denominator: 1 })).toThrow(/never a decimal/)
  })

  it('refuses to divide by zero', () => {
    expect(() => applyRatio(100, { numerator: 1, denominator: 0 })).toThrow(/must not be zero/)
  })
})

describe('format', () => {
  const cases: [number, string][] = [
    [0, '0 ₫'],
    [999, '999 ₫'],
    [1_000, '1.000 ₫'],
    [1_234_567, '1.234.567 ₫'],
    [-1_234_567, '-1.234.567 ₫'],
    [1_000_000_000, '1.000.000.000 ₫'],
  ]

  it.each(cases)('%d → %s', (amount, expected) => {
    expect(format(amount)).toBe(expected)
  })

  const rates: [number, string][] = [
    [1500, '15%'],
    [1000, '10%'],
    [750, '7.5%'],
    [25, '0.25%'],
    [0, '0%'],
    [10_000, '100%'],
  ]

  it.each(rates)('%d bp → %s', (rate, expected) => {
    expect(formatBasisPoints(rate)).toBe(expected)
  })
})
