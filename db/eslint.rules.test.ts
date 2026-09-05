/**
 * The no-await-in-transaction rule is enforcement, not style: `conventions.md`
 * §3 calls it the highest-value guardrail in the repo. A guardrail can stop
 * working silently — a reordered config, a renamed selector, an ESLint upgrade
 * that changes AST node names — and nothing would fail. These tests fail
 * instead.
 *
 * They lint source text through the package's real `eslint.config.js`, so they
 * check the rule as actually configured rather than the selectors in isolation.
 */

import { ESLint } from 'eslint'
import { describe, expect, it } from 'vitest'

const eslint = new ESLint({ cwd: import.meta.dirname })

async function messagesFor(code: string): Promise<string[]> {
  const [result] = await eslint.lintText(code, { filePath: 'fixture.ts' })
  return (result?.messages ?? []).map((m) => `${String(m.ruleId)}: ${m.message}`)
}

const PRELUDE = `
declare function write<T>(fn: (tx: unknown) => T): T
declare const tx: { write<T>(fn: (t: unknown) => T): T }
declare function later(): Promise<number>
declare const stream: AsyncIterable<number>
export {}
`

const violations = (messages: string[]): string[] =>
  messages.filter((m) => m.startsWith('no-restricted-syntax'))

describe('no await inside write()', () => {
  it('rejects a bare await', async () => {
    const messages = await messagesFor(`${PRELUDE}
      export async function f() {
        return write(() => {
          const n = await later()
          return n
        })
      }`)

    expect(violations(messages)).toHaveLength(1)
    expect(violations(messages)[0]).toContain('No await inside write()')
  })

  it('rejects for-await, which a plain await ban would miss', async () => {
    const messages = await messagesFor(`${PRELUDE}
      export function f() {
        return write(() => {
          for await (const n of stream) { console.log(n) }
        })
      }`)

    expect(violations(messages)).toHaveLength(1)
  })

  it('rejects an async callback, which invites both', async () => {
    const messages = await messagesFor(`${PRELUDE}
      export function f() {
        return write(async () => 1)
      }`)

    expect(violations(messages)[0]).toContain('must be synchronous')
  })

  it('rejects the method form, tx.write(...)', async () => {
    const messages = await messagesFor(`${PRELUDE}
      export function f() {
        return tx.write(async () => 2)
      }`)

    expect(violations(messages)).toHaveLength(1)
  })

  it('rejects an await nested deep inside the callback', async () => {
    const messages = await messagesFor(`${PRELUDE}
      export async function f() {
        return write(() => {
          if (true) { while (false) { void (async () => { await later() })() } }
          return 1
        })
      }`)

    expect(violations(messages)).not.toHaveLength(0)
  })

  it('allows a synchronous callback', async () => {
    const messages = await messagesFor(`${PRELUDE}
      export function f() {
        return write(() => 1 + 1)
      }`)

    expect(violations(messages)).toHaveLength(0)
  })

  it('allows awaiting the transaction itself from outside', async () => {
    const messages = await messagesFor(`${PRELUDE}
      export async function f() {
        const before = await later()
        const result = write(() => before + 1)
        const after = await later()
        return result + after
      }`)

    expect(violations(messages)).toHaveLength(0)
  })
})
