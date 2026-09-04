# KPX — API Plan

> Status: rule placement decided; auth **parked** by decision until the backend is
> otherwise complete. Backend first, front end after.

---

## 1. Where the rules execute

### The reframe

It is not "API **or** database". **The API implements every rule regardless** — it has
to, in order to give field-level errors before submit, in Vietnamese, and to say
*"chair 2 is taken, here are the free ones"* rather than one 422 after the fact.

The narrower question is **which rules also keep a backstop underneath**, and that is
what this section decides.

### What a trigger costs, measured

2,000 bookings against the real schema:

| | per write |
|---|---|
| insert only, nothing enforced | 12 µs |
| API checks once, then inserts | 224 µs |
| the 5 booking triggers check inside the insert | 733 µs |

The triggers cost roughly **3× a hand-written check**, because each re-scans
independently where one API query does it in a single pass. At clinic scale — a few
hundred bookings a day — 0.7 ms per booking is irrelevant. **Performance is not the
argument for keeping them.**

### What a trigger buys

**1. Atomicity.** Two receptionists, two devices, the same second. Both check chair 1
at 09:00, both see it free, both book:

```
WITHOUT the trigger — the API did the check
  A checks chair 1 at 09:00 for Dr Minh   -> 0 conflicts, free
  B checks chair 1 at 09:00 for Dr Quynh  -> 0 conflicts, free
  A books -> ok
  B books -> ok
  >> in chair 1 at 09:00: 2 appointment(s)   <-- TWO PATIENTS, ONE CHAIR

WITH the trigger
  A books -> ok
  B books -> REFUSED: chair double-booked: another appointment overlaps this chair
  >> in chair 1 at 09:00: 1 appointment(s)   <-- correct
```

Any check whose answer depends on *other rows* can go stale between the check and the
write. Avoiding it in app code needs `BEGIN IMMEDIATE` around every such command —
doable, easy to forget, and invisible when forgotten until two patients arrive.

**2. It survives our own bugs.** The append-only and immutability rules exist because
the clinic needs the log to audit a doctor's work and resolve legal concerns. An API
bug that overwrites a decision log destroys that record with no recovery.

**3. Derived values stay correct.** Seven triggers *maintain* data rather than validate
it — invoice totals, stock on hand, procedure status tracking the decision log. If the
API forgets one, the data silently drifts.

**4. Every writer is covered** — the API, a migration script, a hand fix in DBeaver, a
future integration.

### The decision rule

| Keep in DB if | Move to API if |
|---|---|
| **(a)** it can be raced — depends on rows another writer could change | **(e)** it is policy management will change (rates, eligibility, thresholds) |
| **(b)** it protects an audit trail — append-only or immutable | **(f)** it is a workflow gate the UI must check anyway for a decent error |
| **(c)** it maintains a derived value | **(g)** it is shape validation of a single row |
| **(d)** it is arithmetic between columns | |

Applied to all 56: **42 keep, 14 move.**

---

## 2. The catalogue — all 56 triggers

### KEEP in the database (42)

#### Append-only and immutability — the audit trail (10)

| Trigger | M | Rule | Why |
|---|---|---|---|
| `trg_decision_no_update` | 4 | a decision cannot be edited | b |
| `trg_decision_no_delete` | 4 | a decision cannot be deleted | b |
| `trg_cond_no_delete` | 5 | a tooth condition is corrected by a new row, never deleted | b |
| `trg_line_immutable_once_issued` | 6 | invoice lines freeze when the invoice leaves Draft | b |
| `trg_att_locked_once_settled` | 8 | a paid shift cannot be edited | b |
| `trg_payroll_locked_once_approved` | 8 | an approved payslip is immutable | b |
| `trg_adj_locked_once_settled` | 8 | a settled adjustment is immutable | b |
| `trg_ce_facts_immutable` | 8 | an entry records work done; only settlement changes | b |
| `trg_notif_content_immutable` | 9 | a sent message is a record of what was sent | b |
| `trg_notif_read_is_one_way` | 9 | a notification cannot be un-read | b |

These never change, cost nothing to keep, and are the difference between an audit trail
and a suggestion.

#### Derived values the API must never be trusted to maintain (7)

| Trigger | M | Maintains |
|---|---|---|
| `trg_decision_applies` | 4 | `treatment_procedure.status` = head of the decision log |
| `trg_invoice_totals_ins` | 6 | invoice subtotal, VAT, total from its lines |
| `trg_line_settles_session` | 6 | session marked billed |
| `trg_line_binds_procedure_price` | 6 | price binding, and the Upfront spread across sessions |
| `trg_payment_settles` | 6 | invoice status from payments received |
| `trg_line_resettles` | 6 | totals after a credit line |
| `trg_log_applies` | 7 | `quantity_on_hand` and batch remainders |

Not validation — bookkeeping. Moving these to the API means every write path must
remember to do it, and the ones that forget fail silently.

#### Race-prone — the answer depends on rows another writer can change (11)

| Trigger | M | Refuses |
|---|---|---|
| `trg_appt_chair_overlap_ins` | 3 | a chair booked twice |
| `trg_appt_chair_overlap_upd` | 3 | the same, on reschedule |
| `trg_appt_doctor_overlap_ins` | 3 | a doctor booked twice |
| `trg_att_no_overlap` | 8 | overlapping shifts, and a second clock-in |
| `trg_payroll_no_overlap` | 8 | overlapping pay periods |
| `trg_log_fefo` | 7 | opening a newer lot while an older one has stock |
| `trg_log_no_expired_consumption` | 7 | using an expired lot on a patient |
| `trg_line_billable_source` | 6 | billing a Declined or Proposed procedure |
| `trg_refund_needs_determination` | 6 | a refund with no credit line and no fault finding |
| `trg_ce_must_have_worked` | 8 | commission to someone who did not work the session |
| `trg_notif_target_exists` | 9 | a notification pointing at a row that is not there |

`trg_notif_target_exists` is a foreign key that SQLite cannot express, because it points
at eight tables. It is not optional.

#### Arithmetic between columns (6)

| Trigger | M | Checks |
|---|---|---|
| `trg_ce_amount_matches_rule` | 8 | amount = base × the rate cited |
| `trg_ce_base_is_session_value` | 8 | base = the session's own billable amount |
| `trg_att_minutes_match` / `_upd` | 8 | minutes = the clock |
| `trg_invoice_issue_validates` | 6 | an invoice is coherent at the moment it is issued |
| `trg_payroll_approval_validates` | 8 | every payslip total recomputed from its linked rows at approval |

The last two are gates, not row checks — they are what makes "Draft → gather → approve"
a real sequence rather than a convention, and both were added because an audit found
totals that followed from nothing.

#### Cross-patient ownership and the fraud control (8)

| Trigger | M | Refuses |
|---|---|---|
| `trg_ce_not_own_treatment` | 8 | **commission on your own treatment** |
| `trg_ptooth_condition_same_patient` | 5 | a finding from another patient's mouth |
| `trg_notif_patient_sees_own` | 9 | telling a patient about another patient's care |
| `trg_ce_settles_into_own_period` / `_upd` | 8 | commission paid into someone else's payslip |
| `trg_adj_settles_into_own_record` / `_upd` | 8 | an adjustment settled onto the wrong person |
| `trg_decision_chain` | 4 | a broken or backdated decision chain |

`trg_ce_not_own_treatment` is the rule this design has carried from the beginning. It is
a policy rule, and by the letter of the decision rule it could move — it stays because
it is the one rule whose failure is *fraud*, and a backstop for fraud is worth 20 µs.

> **One thing to lift out of `trg_decision_chain`:** the legal-transition map
> (Proposed → Accepted → Scheduled → …) is policy and belongs in the API. The chain's
> *integrity* — `from_status` matching, and decisions never moving backwards in time —
> stays.

---

### MOVE to the API (14)

| Trigger | M | Rule | Why it moves |
|---|---|---|---|
| `trg_appt_doctor_bookable` | 3 | no booking an OnLeave or Departed doctor | f — the picker should not offer them |
| `trg_appt_chair_available` | 3 | the chair must be Available | f — same, and chair status changes |
| `trg_proc_material_required` | 4 | material-priced procedures need a material chosen | g — a form field |
| `trg_cond_surfaces_valid` | 5 | surfaces must be canonical for that tooth | g — reference data, no race |
| `trg_ptooth_surfaces_valid` | 5 | the same on the procedure side | g |
| `trg_session_needs_accepted` | 5 | no session on an unaccepted procedure | f — a workflow gate |
| `trg_log_batch_required` | 7 | a material movement names its lot | g |
| `trg_batch_starts_empty` | 7 | a new batch starts empty, filled by a Restocked log | g |
| `trg_log_procedure_must_have_started` / `_upd` | 7 | no consumption on work not started | f |
| `trg_ce_cites_the_applicable_rule` | 8 | rate resolution: contract → category → role | **e — this changes** |
| `trg_att_hourly_only` | 8 | only hourly staff clock in | e |
| `trg_rpl_is_a_receptionist` | 8 | only a receptionist earns the bounty | e |
| `trg_notif_not_to_departed` | 9 | no paging someone who has left | e |

`trg_ce_cites_the_applicable_rule` is the important one. Rate resolution is exactly what
a manager changes without wanting a migration. **But the resolution logic must not exist
twice**, so before it moves, add:

```sql
CREATE VIEW v_commission_due AS   -- completed sessions with no entry yet,
                                  -- joined to the rule that resolves for that
                                  -- staff member and that work
```

Then `completeSession` inserts straight from the view, and neither the API nor a second
copy of the precedence order can drift from it.

---

## 3. Migration order

1. **Add `v_commission_due`** (and a payroll-draft equivalent), so nothing has to be
   reimplemented before it can be removed.
2. **Port the 14 into the API's command layer**, each with the negative tests that
   already prove it — retargeted from SQL to HTTP.
3. **Drop the 14 from the schema files.** Delete, do not comment: commented SQL is not
   compiled, not tested, and unreadable as intent within two months. Git holds every
   version (`git show <sha>:db/modules/0801_payroll_schema.sql`).
4. **Keep the 42**, and keep their negative tests running against the database directly —
   they are the backstop's own test suite.

The 42 that stay never need touching again. The 14 that move are the ones a manager will
ask to change.
