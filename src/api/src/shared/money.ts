/**
 * Money. Integer **đồng**, and every formula that touches it.
 *
 * `conventions.md` §5: VND has no minor unit, so there is no `_cents` and never
 * a float. Stored columns are suffixed `_vnd`. No arithmetic on money happens
 * inline in a use case — it happens here, or in a module's `domain/`.
 *
 * ## Rates are integers too
 *
 * An integer multiplied by a floating-point rate is still floating-point
 * arithmetic. Percentages are **basis points**: integers where 1 bp = 0.01%.
 *
 * ```ts
 * applyBasisPoints(1_000_000, 1500)   // ✓ 15.00%
 * applyBasisPoints(1_000_000, 0.15)   // ✗ throws: 0.15 is not an integer
 * ```
 *
 * | Rate | Basis points |
 * |---|---|
 * | 15%   | 1500 |
 * | 8%    |  800 |
 * | 7.5%  |  750 |
 * | 0.25% |   25 |
 *
 * ## Agreement with the schema
 *
 * `invoice_line` carries a CHECK that computes VAT in SQL, in floating point:
 *
 * ```sql
 * vat_amount = CAST(ROUND((line_total - discount_amount) * vat_rate / 100.0) AS INTEGER)
 * ```
 *
 * so a value computed here that differs by a single đồng is rejected on insert.
 * `applyBasisPoints` uses exact integer arithmetic and rounds half away from
 * zero, which is what SQLite's `ROUND` does — measured, not assumed, against
 * every exact tie at 0%, 5%, 8%, 10%, 2.5%, 7.5% and 8.5%: **no disagreement**.
 *
 * The two *can* diverge, and it is worth knowing where. At a rate whose decimal
 * form is poorly representable in binary — 0.29%, say — float error drags
 * SQLite's result below the tie and it rounds down where exact arithmetic rounds
 * up: 25,000 đồng at 0.29% is 72 in SQL and 73 here. No such rate is a plausible
 * VAT rate, and `money.matches-schema.test.ts` pins the ones that are. If a rate
 * like that is ever introduced, that test is where it will surface.
 */

/** An amount in whole đồng. Negative means a credit. */
export type Vnd = number

/** Hundredths of a percent. 1500 is 15.00%. */
export type BasisPoints = number

/** A rate that is genuinely a ratio rather than a percentage (§5). */
export interface Ratio {
  numerator: number
  denominator: number
}

export const ZERO: Vnd = 0

const BASIS_POINT_SCALE = 10_000

/**
 * Every rounding point is a **named policy**, never an inline `Math.round`
 * (§5). Naming them means a test can pin each one, and a reader can see which
 * was chosen without reconstructing the arithmetic.
 */
export type Rounding =
  /** Ties go away from zero: 2.5 → 3, −2.5 → −3. Matches SQLite's `ROUND`. */
  | 'half-away-from-zero'
  /** Always toward zero: 2.9 → 2, −2.9 → −2. Used where a remainder is carried. */
  | 'toward-zero'

export function assertVnd(value: number, what = 'amount'): void {
  if (!Number.isInteger(value)) {
    throw new RangeError(`${what} must be whole đồng, got ${String(value)}`)
  }
  if (!Number.isSafeInteger(value)) {
    throw new RangeError(`${what} is too large to be exact: ${String(value)}`)
  }
}

export function assertBasisPoints(rate: number): void {
  if (!Number.isInteger(rate)) {
    throw new RangeError(
      `rate must be basis points — an integer where 1500 is 15% — got ${String(rate)}. ` +
        'A decimal here means a floating-point rate slipped through (conventions.md §5).',
    )
  }
}

export function add(...amounts: Vnd[]): Vnd {
  return sum(amounts)
}

export function sum(amounts: readonly Vnd[]): Vnd {
  let total = 0
  for (const amount of amounts) {
    assertVnd(amount)
    total += amount
  }
  assertVnd(total, 'total')
  return total
}

export function subtract(from: Vnd, amount: Vnd): Vnd {
  assertVnd(from)
  assertVnd(amount)
  return from - amount
}

/** The opposite sign. A credit line is a negated charge, not a deletion (§6). */
export function negate(amount: Vnd): Vnd {
  assertVnd(amount)
  return -amount
}

/** An amount times a whole quantity — a line total, before any rate. */
export function multiply(amount: Vnd, quantity: number): Vnd {
  assertVnd(amount)
  if (!Number.isInteger(quantity)) {
    throw new RangeError(`quantity must be whole, got ${String(quantity)}`)
  }
  const total = amount * quantity
  assertVnd(total, 'line total')
  return total
}

/**
 * There is no negative zero amount of money. `Math.trunc(-0/n)` produces one,
 * and it survives far enough to print as "-0 ₫" or to fail an equality check
 * against a perfectly ordinary 0. Collapsed here, at the one exit every rounded
 * result passes through.
 */
function normalise(amount: number): Vnd {
  return amount === 0 ? 0 : amount
}

/**
 * Divides exactly, then applies the named policy. Kept private so every rounding
 * point in the system arrives through a function that names its policy.
 */
function divideRounded(numerator: number, denominator: number, rounding: Rounding): Vnd {
  if (!Number.isSafeInteger(numerator)) {
    throw new RangeError(
      `intermediate ${String(numerator)} exceeds exact integer range; the amount or rate is too large`,
    )
  }
  const quotient = Math.trunc(numerator / denominator)
  const remainder = Math.abs(numerator % denominator)
  if (rounding === 'toward-zero' || remainder === 0) return normalise(quotient)
  const roundsUp = remainder * 2 >= Math.abs(denominator)
  return normalise(roundsUp ? quotient + Math.sign(numerator) : quotient)
}

/**
 * A percentage of an amount, as basis points.
 *
 * Defaults to `half-away-from-zero` because that is what the schema's VAT CHECK
 * does, and a mismatch there is an insert that fails rather than a number that
 * looks slightly off.
 */
export function applyBasisPoints(
  amount: Vnd,
  rate: BasisPoints,
  rounding: Rounding = 'half-away-from-zero',
): Vnd {
  assertVnd(amount)
  assertBasisPoints(rate)
  return divideRounded(amount * rate, BASIS_POINT_SCALE, rounding)
}

/** A share of an amount expressed as an explicit ratio rather than a percentage. */
export function applyRatio(
  amount: Vnd,
  ratio: Ratio,
  rounding: Rounding = 'half-away-from-zero',
): Vnd {
  assertVnd(amount)
  if (!Number.isInteger(ratio.numerator) || !Number.isInteger(ratio.denominator)) {
    throw new RangeError('a ratio is two integers — never a decimal (conventions.md §5)')
  }
  if (ratio.denominator === 0) throw new RangeError('ratio denominator must not be zero')
  return divideRounded(amount * ratio.numerator, ratio.denominator, rounding)
}

/**
 * Splits an amount across weights so the parts **sum exactly to the whole**.
 *
 * This is the policy §5 fixes for invoice discounts: pro-rata by line value,
 * rounded down, with the remainder on the last line. Rounding each share
 * independently would leave the shares one or two đồng short of the discount
 * actually granted, and that gap lands in a legal invoice.
 *
 * Zero-weight entries get zero, and the remainder goes to the last entry that
 * carries weight — never to a line that was allocated nothing.
 */
export function allocate(total: Vnd, weights: readonly number[]): Vnd[] {
  assertVnd(total)
  if (weights.length === 0) return []
  for (const weight of weights) {
    if (!Number.isInteger(weight) || weight < 0) {
      throw new RangeError(`weights must be whole and non-negative, got ${String(weight)}`)
    }
  }

  const totalWeight = weights.reduce((a, b) => a + b, 0)
  // Nothing to weigh by: the whole amount cannot be attributed, so refuse rather
  // than invent a split.
  if (totalWeight === 0) {
    if (total === 0) return weights.map(() => 0)
    throw new RangeError('cannot allocate a non-zero amount across zero total weight')
  }

  const shares = weights.map((weight) =>
    divideRounded(total * weight, totalWeight, 'toward-zero'),
  )
  const remainder = total - shares.reduce((a, b) => a + b, 0)

  let last = -1
  for (let i = 0; i < weights.length; i++) if ((weights[i] ?? 0) > 0) last = i
  shares[last] = (shares[last] ?? 0) + remainder
  return shares
}

/**
 * For logs, tests and exports. **Not for the UI** — display formatting is the
 * front end's job (§4), and it has the user's locale and this does not.
 *
 * Grouped by dots, Vietnamese style, and written by hand rather than through
 * `Intl` so the output cannot shift with an ICU version.
 */
export function format(amount: Vnd): string {
  assertVnd(amount)
  const digits = Math.abs(amount).toString()
  let grouped = ''
  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) grouped += '.'
    grouped += digits[i]
  }
  return `${amount < 0 ? '-' : ''}${grouped} ₫`
}

/** `1500` → `"15%"`, `750` → `"7.5%"`. For the same audience as `format`. */
export function formatBasisPoints(rate: BasisPoints): string {
  assertBasisPoints(rate)
  const whole = Math.trunc(rate / 100)
  const fraction = Math.abs(rate % 100)
  if (fraction === 0) return `${String(whole)}%`
  const text = fraction % 10 === 0 ? String(fraction / 10) : String(fraction).padStart(2, '0')
  return `${String(whole)}.${text}%`
}
