/**
 * The coverage gate for `shared/errors` (`conventions.md` §8).
 *
 * It counts entries and checks the map against the schema. It does **not**
 * assert wording: change the `en` of any code and nothing here fails, which is
 * the whole point — forty rule tests must not break because someone rephrased a
 * message, and Vietnamese must not break them either. Delete an entry and this
 * fails while the rule tests still pass. That separation is the design.
 */

import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

import { describe, expect, it } from 'vitest'

import { CATALOGUE, isCatalogued, messageFor, type CatalogueEntry } from './catalogue.js'
import { CONSTRAINT_TO_CODE } from './constraint-map.js'
import {
  CONSTRAINT_VIOLATED,
  DUPLICATE_VALUE,
  REFERENCED_ROW_MISSING,
  REQUIRED_FIELD_MISSING,
} from './translate.js'
import { INTERNAL_ERROR_CODE, NOT_FOUND_CODE, VALIDATION_FAILED_CODE } from './handler.js'

const entries = Object.entries(CATALOGUE) as [string, CatalogueEntry][]

/** The named constraints as they actually appear in the schema, read from the SQL. */
function namedConstraintsInSchema(): string[] {
  const dir = join(import.meta.dirname, '../../../../../db/modules')
  const names = readdirSync(dir)
    .filter((f) => f.endsWith('_schema.sql'))
    .flatMap((f) => [...readFileSync(join(dir, f), 'utf8').matchAll(/CONSTRAINT\s+(ck_\w+)\s+CHECK/g)])
    .map((m) => m[1] as string)
  return [...new Set(names)].sort()
}

describe('every catalogued code', () => {
  it('has non-empty English', () => {
    const empty = entries.filter(([, e]) => e.en.trim() === '')

    expect(empty.map(([code]) => code)).toEqual([])
  })

  it('has vi null until Phase J fills it in', () => {
    const translated = entries.filter(([, e]) => e.vi !== null)

    expect(translated.map(([code]) => code)).toEqual([])
  })

  it('is SCREAMING_SNAKE_CASE, so codes stay greppable', () => {
    const odd = entries.filter(([code]) => !/^[A-Z][A-Z0-9_]*$/.test(code))

    expect(odd.map(([code]) => code)).toEqual([])
  })

  it('carries a rule number only where a rule-catalogue rule exists', () => {
    const outOfRange = entries.filter(([, e]) => e.rule !== null && (e.rule < 1 || e.rule > 89))

    expect(outOfRange.map(([code]) => code)).toEqual([])
  })
})

describe('the codes this module can emit', () => {
  const emitted = [
    CONSTRAINT_VIOLATED,
    REFERENCED_ROW_MISSING,
    DUPLICATE_VALUE,
    REQUIRED_FIELD_MISSING,
    INTERNAL_ERROR_CODE,
    NOT_FOUND_CODE,
    VALIDATION_FAILED_CODE,
  ]

  it.each(emitted)('%s is catalogued', (code) => {
    expect(isCatalogued(code)).toBe(true)
  })
})

describe('the constraint map', () => {
  it('covers all 65 named constraints', () => {
    expect(Object.keys(CONSTRAINT_TO_CODE)).toHaveLength(65)
  })

  it('maps every constraint to a catalogued code', () => {
    const uncatalogued = Object.entries(CONSTRAINT_TO_CODE).filter(([, code]) => !isCatalogued(code))

    expect(uncatalogued).toEqual([])
  })

  it('gives each constraint its own code — a shared one would hide which rule refused', () => {
    const codes = Object.values(CONSTRAINT_TO_CODE)

    expect(new Set(codes).size).toBe(codes.length)
  })

  it('names only constraints that exist in the schema', () => {
    const inSchema = new Set(namedConstraintsInSchema())
    const stale = Object.keys(CONSTRAINT_TO_CODE).filter((name) => !inSchema.has(name))

    expect(stale).toEqual([])
  })

  it('names every constraint the schema declares — a new one must not go unmapped', () => {
    const mapped = new Set(Object.keys(CONSTRAINT_TO_CODE))
    const unmapped = namedConstraintsInSchema().filter((name) => !mapped.has(name))

    expect(unmapped).toEqual([])
  })
})

describe('messageFor', () => {
  it('returns the English for a known code', () => {
    expect(messageFor('DUPLICATE_VALUE')).toBe(CATALOGUE.DUPLICATE_VALUE.en)
  })

  it('returns undefined for an unknown code rather than inventing wording', () => {
    expect(messageFor('NOT_A_REAL_CODE')).toBeUndefined()
  })

  it('is not fooled by inherited object properties', () => {
    expect(messageFor('toString')).toBeUndefined()
    expect(messageFor('constructor')).toBeUndefined()
  })
})
