/**
 * `applyBasisPoints` must agree with the SQL that `invoice_line` enforces:
 *
 * ```sql
 * vat_amount = CAST(ROUND((line_total - discount_amount) * vat_rate / 100.0) AS INTEGER)
 * ```
 *
 * A single đồng of disagreement is not a rounding nit — it is an insert the
 * database refuses, in Phase F, on a legal invoice.
 *
 * This is the one test in `shared/` that opens a database, deliberately: the
 * claim being checked is about SQLite's arithmetic, and nothing but SQLite can
 * settle it. `money.test.ts` stays pure. In memory, so it costs milliseconds.
 */

import { Sqlite } from '@kpx/db'
import { afterAll, describe, expect, it } from 'vitest'

import { applyBasisPoints } from './money.js'

// Through @kpx/db, which owns the driver — a second copy in this package
// would put two native modules in the tree (step 3).
const sqlite = new Sqlite(':memory:')
const vatInSql = sqlite.prepare(
  'SELECT CAST(ROUND(? * ? / 100.0) AS INTEGER) AS vat',
)

afterAll(() => {
  sqlite.close()
})

/** The schema stores a percentage; this module speaks basis points. */
const asPercent = (basisPoints: number): number => basisPoints / 100

const vatFromSql = (amount: number, basisPoints: number): number =>
  (vatInSql.get(amount, asPercent(basisPoints)) as { vat: number }).vat

/** Vietnamese VAT rates that actually occur, plus the plausible fractional ones. */
const RATES: [label: string, basisPoints: number][] = [
  ['0%', 0],
  ['5%', 500],
  ['8%', 800],
  ['10%', 1000],
  ['2.5%', 250],
  ['7.5%', 750],
  ['8.5%', 850],
]

describe.each(RATES)('VAT at %s', (_label, basisPoints) => {
  it('agrees with the schema across a spread of amounts', () => {
    for (let amount = 0; amount <= 2_000_000; amount += 1237) {
      expect(applyBasisPoints(amount, basisPoints)).toBe(vatFromSql(amount, basisPoints))
    }
  })

  it('agrees on exact ties, where rounding policy actually shows', () => {
    let ties = 0
    for (let amount = 1; amount <= 400_000 && ties < 2_000; amount++) {
      if (basisPoints !== 0 && (amount * basisPoints) % 10_000 !== 5_000) continue
      ties++
      expect(applyBasisPoints(amount, basisPoints)).toBe(vatFromSql(amount, basisPoints))
    }
  })

  it('agrees on credits, which carry VAT the same way', () => {
    for (let amount = -200_000; amount < 0; amount += 997) {
      expect(applyBasisPoints(amount, basisPoints)).toBe(vatFromSql(amount, basisPoints))
    }
  })
})

describe('where the two would diverge', () => {
  it('a rate whose decimal form is poorly representable disagrees at a tie', () => {
    // 0.29%: 25000 × 29 / 10000 is exactly 72.5, so exact arithmetic rounds away
    // from zero to 73. In SQL, 25000 * 0.29 lands just under 7250, so ROUND gives
    // 72. Documented rather than fixed — no such rate is a plausible VAT rate,
    // and this test is where one would announce itself.
    expect(applyBasisPoints(25_000, 29)).toBe(73)
    expect(vatFromSql(25_000, 29)).toBe(72)
  })

  it('none of the rates the clinic actually uses behaves that way', () => {
    const disagreements = RATES.filter(([, basisPoints]) => {
      for (let amount = 1; amount <= 100_000; amount++) {
        if (applyBasisPoints(amount, basisPoints) !== vatFromSql(amount, basisPoints)) return true
      }
      return false
    })

    expect(disagreements).toEqual([])
  })
})
