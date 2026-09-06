# KPX — Decisions

What changed, why, and which workflow docs and tests moved with it
(`conventions.md` §14). Newest first.

---

## 2026-09-06 — Time handling policy: scheduling is business time, events are UTC

**Was:** `conventions.md` §4 said an Instant is stored as ISO-8601 UTC. The schema and seed,
written earlier, store naive clinic wall time in every column and never mention a timezone.
My first answer was to make everything clinic-local and put the offset on the wire; that kept
the views working but treated scheduling and auditing as one problem.

**Now:** they are two problems with two answers.

| Kind | Type | Stored as |
|---|---|---|
| *when the clinic will see you* | `LocalDate` + `LocalTime` | as written, never converted |
| *when something happened* | `Instant` | UTC |

**Why.** An appointment at 10:00 on 10 September is a fact about the clinic's day — 10:00
whether the patient is in Hanoi or New York — so converting it to anyone's zone changes what
it means. "When did the patient press Book" is the opposite: one moment, observed from
wherever they were, and only UTC keeps ordering and causality straight across clients in
different zones. Storing both the same way forces one of them to be wrong.

The timezone is stored as an IANA name rather than `+07:00`. Vietnam has been UTC+7 for
decades, but the business rule is "the time at the clinic in Vietnam", and the name survives a
change of law where an offset silently would not.

**Consequences**

- `shared/time.ts` carries three branded types and no fourth. `toInstant` refuses an
  offset-bearing string rather than normalising it: if one arrives, some layer is passing
  along a client's clock.
- `instantOfSlot(date, time)` derives an absolute moment for reminders, jobs and calendar
  exports. Derived — the business fact stays the date and the time.
- **Book a slot, not a time.** Where a slot exists the client sends `slotId` and nothing else,
  so the front end does no timezone arithmetic and the API claims an existing row
  transactionally — closing the double-booking race and the timezone one together. No slot
  entity exists yet; see below.

**Migration, staged.** `db/modules/**` is unfrozen for this, by decision, but not in one PR:

1. **This PR** — the policy, and `shared/time.ts` matching it. Stops new code writing the
   wrong shape. No schema change.
2. **Audit columns → UTC.** 29 columns across 9 modules currently hold clinic-local in the
   seed; ~256 datetime literals shift by −7h. `DEFAULT (datetime('now'))` is already UTC and
   becomes correct rather than a trap.
3. **`appointment.scheduled_at` → `appointment_date` + `start_time`.** Touches 5 views, 3
   indexes and `v_appt_outside_schedule`. Cheapest now, before Phase B1 builds rule 2 and the
   day sheet on top of it.
4. **A slot entity**, if adopted — a design change to Phase B1 and Phase P, not a migration.

---

## 2026-09-05 — Authentication is scheduled between the clinic app and the patient app

**Was:** real authentication lived in Phase J (Hardening), at the end. The stub —
an `X-Acting-User` header — carried everything until then.

**Now:** auth is revisited **after the first version of the clinic app works, and
before any patient portal UI is built.** In phase terms that is after **C**, before
**P**. Phase J keeps the rest of hardening.

**Why.** The clinic app is internal and its users are known, so a header stub is a
tolerable placeholder there. The patient app is on the public internet, and its
authenticated half shows a person their own treatment record. Shipping that behind
a header anyone can set is not a shortcut, it is a data breach. The two apps have
genuinely different deadlines for the same problem, and pretending otherwise
pushed the harder one to the end of the plan.

This mostly ratifies what the plan already implied: Phase P was always the public
half only, and Phase P2 was always blocked on auth. What changes is that auth stops
being the last thing and becomes a scheduled step with a place in the order.

**Consequences**

- Phase P (public patient app: services, address, contact, booking request) is
  unaffected. It needs no auth and can ship before this work.
- Phase P2 (the authenticated patient portal) stays blocked, now on this step
  rather than on all of Phase J.
- `open-questions.md` #6, the deployment origin, becomes blocking for this step
  rather than for Phase J: first-party cookie versus bearer token follows from it.
- Until then the clinic UI signs in with mock users — real rows from the seed,
  chosen in a dev-only switcher, sent as `X-Acting-User`. It exercises the real
  guard, including the refusals, without a login screen existing yet.

**Tests and docs that moved:** none. No behaviour changed, so no test changed. The
step-6 guard already refuses a Departed or OnLeave staff member and already
declines to register `/api/patient/*`.

---

## 2026-09-05 — `ALLOW_STUB_AUTH` defaults to on outside production

**Was:** the API refused to start unless `ALLOW_STUB_AUTH=true` was set explicitly,
in every environment. `.env.example` documented the variable but nothing loaded
`.env`, so a clean clone could not run `npm run dev` at all.

**Now:** `src/api/.env` is loaded if present (Node's own `process.loadEnvFile`, no
dependency), and an unset `ALLOW_STUB_AUTH` means **on outside production, off in
production**. Set explicitly it still means exactly what it says, and a misspelled
value still reads as off.

**Why.** The accident worth preventing is a production deploy still trusting a
header anyone can set — not a developer running the clinic app on a laptop. The
original rule paid for the same protection with friction on every developer, every
day, and friction that everyone routes around stops being protection.

**Tests:** `src/api/src/config.test.ts` pins the default in both directions, since
it is a security decision rather than a convenience.
