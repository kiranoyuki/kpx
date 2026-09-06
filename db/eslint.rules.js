/**
 * Shared lint rules. Duplicated into each package's own `eslint.config.js`
 * import rather than published, because the packages share no mutable file.
 *
 * ## no-await-in-transaction
 *
 * `conventions.md` §3: one `await` inside `write()` splits the synchronous
 * block and reopens every check-then-act race — chair and doctor overlap,
 * FEFO, stock levels, overlapping shifts and pay periods. Nothing fails; the
 * guarantee just stops being true. This is the highest-value guardrail in the
 * repo, which is why it is a lint error rather than a convention.
 *
 * Three shapes are caught, because banning only `await` would leave two holes:
 *
 *   write(() => { await x })          AwaitExpression
 *   write(() => { for await (…) {} }) ForOfStatement[await=true]
 *   write(async () => {})             an async callback, which invites both
 *
 * Matching is on the callee name, so `write(…)` and `tx.write(…)` are both
 * covered. It is deliberately syntactic: a rule that tried to resolve which
 * `write` this is would need type information, and would then miss the cases
 * that matter most — the ones written in a hurry.
 */

const WRITE_CALL = ':matches(CallExpression[callee.name="write"], CallExpression[callee.property.name="write"])'

const AWAIT_MESSAGE =
  'No await inside write(): it splits the synchronous transaction and reopens every ' +
  'check-then-act race (conventions.md §3). Move the awaited work outside the ' +
  'transaction, or record it in an outbox row and dispatch it after commit.'

const ASYNC_CALLBACK_MESSAGE =
  'The write() callback must be synchronous (conventions.md §3). An async callback ' +
  'returns a Promise, so the transaction commits before its work has finished.'

export const noAwaitInTransaction = {
  'no-restricted-syntax': [
    'error',
    { selector: `${WRITE_CALL} AwaitExpression`, message: AWAIT_MESSAGE },
    { selector: `${WRITE_CALL} ForOfStatement[await=true]`, message: AWAIT_MESSAGE },
    {
      selector: `${WRITE_CALL} > :matches(ArrowFunctionExpression, FunctionExpression)[async=true]`,
      message: ASYNC_CALLBACK_MESSAGE,
    },
  ],
}

/**
 * ## no-ambient-time
 *
 * `conventions.md` §4: business logic never reaches for the current time, it
 * receives it. A bare `new Date()` or `Date.now()` makes a rule untestable —
 * "cancellation is inside the 24-hour window" can then only be checked by
 * recomputing the answer the same way the code does, which tests nothing.
 *
 * `shared/clock.ts` is the one exception, and is exempted where this is applied.
 */
const AMBIENT_TIME_MESSAGE =
  'No ambient time here (conventions.md §4). Take a Clock as a dependency and call ' +
  'clock.now(); shared/clock.ts is the only module allowed to read the machine clock.'

export const noAmbientTime = {
  'no-restricted-syntax': [
    'error',
    {
      selector: 'NewExpression[callee.name="Date"][arguments.length=0]',
      message: AMBIENT_TIME_MESSAGE,
    },
    {
      selector: 'CallExpression[callee.object.name="Date"][callee.property.name="now"]',
      message: AMBIENT_TIME_MESSAGE,
    },
    {
      // new Date('2026-08-20') parses as UTC midnight, which is 07:00 the same
      // day in Ho Chi Minh City — so a pay period, an expiry or a day sheet
      // computed that way silently shifts by a day for part of every day.
      selector: 'NewExpression[callee.name="Date"] > Literal[value=/^\\d{4}-\\d{2}-\\d{2}$/]',
      message:
        'Do not build a Date from a calendar day (conventions.md §4). It parses as UTC ' +
        'midnight, which is 07:00 the same day in the clinic, so the answer is a day out ' +
        'for part of every day. Use LocalDate from shared/time.ts, which never round-trips ' +
        'through a Date.',
    },
  ],
}
