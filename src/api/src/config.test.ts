/**
 * The stub-auth default is a security decision, so it is pinned here rather
 * than left to whoever reads the ternary next.
 */
import { describe, expect, it } from 'vitest'

import { __parseAllowStubAuthForTest as parseAllowStubAuth } from './config.js'

describe('ALLOW_STUB_AUTH', () => {
  it('is on by default outside production, so a clean clone runs', () => {
    expect(parseAllowStubAuth(undefined, 'development')).toBe(true)
    expect(parseAllowStubAuth(undefined, 'test')).toBe(true)
  })

  it('is OFF by default in production — the accident actually worth preventing', () => {
    expect(parseAllowStubAuth(undefined, 'production')).toBe(false)
  })

  it('honours an explicit true, even in production', () => {
    expect(parseAllowStubAuth('true', 'production')).toBe(true)
  })

  it('honours an explicit false, even in development', () => {
    expect(parseAllowStubAuth('false', 'development')).toBe(false)
  })

  it('treats a misspelled value as off, never as on', () => {
    expect(parseAllowStubAuth('TRUE', 'development')).toBe(false)
    expect(parseAllowStubAuth('1', 'development')).toBe(false)
    expect(parseAllowStubAuth('yes', 'development')).toBe(false)
  })
})
