# KPX Database

Built one module at a time, following `Design/build-plan.md`.
`Design/core-entities/entities.md` is the source of truth for the model.

**Status: modules 1–7 of 9 complete.**

| # | Module | Entities | Built |
|---|--------|----------|-------|
| 1 | People & Access | app_user, staff_profile, patient_profile | ✅ |
| 2 | Clinic Setup | tooth, chair_type, chair, service_category, material_option, price_list, promotion | ✅ |
| 3 | Scheduling | doctor_schedule, appointment | ✅ |
| 4 | Treatment Planning | treatment_plan, procedure_instruction, treatment_procedure, procedure_decision, discount_proposal, special_procedure_proposal | ✅ |
| 5 | Clinical Record | health_record, tooth_condition, procedure_tooth, patient_media, procedure_session | ✅ |
| 6 | Billing | invoice, invoice_line, payment, treatment_failure | ✅ |
| 7 | Inventory | vendor, inventory_item, inventory_batch, inventory_log, procedure_supply_list, equipment, equipment_maintenance | ✅ |
| 8 | Payroll & Commission | wage_rate, attendance_log, payroll_record, commission_rule, receptionist_performance_log, commission_entry, payroll_adjustment | ✅ |
| 9 | Notifications | notification | ✅ |
| 8 | Payroll & Commission | wage_rate, attendance_log, payroll_record, commission_rule, receptionist_performance_log, commission_entry, payroll_adjustment | — |
| 9 | Notifications | notification | — |

## Build

```bash
./db/build.sh
```

Replays every file in `db/modules/` in order. The `.db` is a build artefact and
is gitignored; the `.sql` files are the source of truth.

### If your SQL client cannot see new tables

**Disconnect and Reconnect — Refresh is not enough.**

The build writes to a temp file and copies it over `kpx.db` in place, so the
inode is preserved and an open connection normally survives. An earlier version
deleted the file first, which gave it a new inode on every build. On macOS,
deleting a file a program still has open keeps the old data alive for that
program, so a GUI client goes on reading a *ghost* of the database as it was
when it first connected. Refresh only re-reads metadata over that same open
handle; it never reopens the file, so it cannot help.

In DBeaver: right-click the connection -> **Invalidate/Reconnect**, or
Disconnect then Connect. Confirm you are pointed at:

```
/Users/anhle/Documents/KPX/db/kpx.db
```

then expand **kpx -> Schemas -> main -> Tables**.

## File naming

`MMSS_name.sql` — **MM** is the module number, **SS** the order within it
(`01` schema, `09` seed).

The all-digit prefix is deliberate. A plain `01_x.sql` / `01_x_seed.sql` pair
sorts *differently* under `en_US.UTF-8` than under `C`, and the seed silently
runs before its schema. `build.sh` also pins `LC_ALL=C`.

## Conventions

- **ids** — `TEXT`. Seed data uses readable slugs (`u-doc01`, `pp-05`); production uses UUIDs.
- **timestamps** — `TEXT`, ISO-8601. **dates** — `TEXT`, `YYYY-MM-DD`.
- **booleans** — `INTEGER` 0/1. **enums** — `TEXT` + `CHECK`.
- **money** — `NUMERIC`, VND, whole numbers (arrives with module 6).
- `app_user` maps to the `User` entity; renamed because `user` is reserved in PostgreSQL.

**Foreign keys are OFF by default in SQLite.** Every connection must issue
`PRAGMA foreign_keys = ON;`.

---

## Module 1 — People & Access

`app_user` is a **person record, not a login**. Every human has exactly one row.
Identity lives there once; the profiles hold only employment or care data and
carry no names.

Authentication is deliberately unmodelled — there are no credential columns.
Patients will identify by `full_name` + `phone` + `national_id`, or by a
one-time code to `phone`. Both read columns already present, so credential
storage can be designed later without touching this table.

### Portal access comes from the profile, never from `role`

| Portal | Granted when |
|--------|--------------|
| Patient | `app_user.status = 'Active'` **and** a `patient_profile` exists |
| Staff | `app_user.status = 'Active'` **and** a `staff_profile` with `employment_status` in (`Intern`, `Active`) |

`role` then governs permissions *inside* the staff portal. Query `v_portal_access`.

### Views

| View | Answers |
|------|---------|
| `v_portal_access` | Who reaches which portal, and why |
| `v_identity_funnel` | How many people sit at each lifecycle stage |
| `v_dual_profile` | Staff who are also patients at their own clinic |

### What the seed exercises

13 people, chosen for the edges rather than the happy path:

| Person | Case |
|--------|------|
| Bùi Thị Hạnh, Ngô Quang Huy | **Provisional** — booked online, never arrived. No CCCD, no verification, and deliberately **no `patient_profile`**. Not patients; people holding a booking. |
| Phạm Thị Ngọc, Lý Văn Hùng | Walk-ins with **no email** — fully Active patients with a CCCD who would sign in by phone code |
| Đỗ Văn Nam | **Intern** — working, assignable, reaches the staff portal. The difference from Active is terms, not access |
| Lê Thị Mai | **OnLeave** — maternity. Not bookable, but not gone: no portal, employment intact |
| **Ngô Bảo Châu** | **Departed doctor who is still a patient.** Keeps the patient portal, loses the staff one, `app_user.status` untouched |
| **Trần Văn Minh** | Serving doctor who is **also a patient** — one person, both profiles, one CCCD |
| Nguyễn Thị Hương | The manager self-verifies: a bootstrap case, since the owner set the system up before anyone existed to check her documents |

### Verification

`PRAGMA integrity_check` ok, `PRAGMA foreign_key_check` zero rows, and **15
negative tests** proving each constraint rejects bad data:

- `national_id` — 11 digits, 13 digits, a letter, a duplicate
- lifecycle — `Active` with no verifier, `Active` half-verified, `Provisional` claiming verification, duplicate email
- employment — `Departed` with no `end_date`, `end_date` while Active, `end_date` before `join_date`, a second `staff_profile` for one person
- care — `patient_profile` with no user, a second one for the same person, one for a nonexistent user

Transitions verified end to end: a Provisional booker arriving and converting to
an Active patient, and a serving doctor departing while remaining an active
person with the patient portal intact.


---

## Module 2 — Clinic Setup

Reference and configuration data: 52 teeth, 4 chair types, 5 chairs, 9 services,
11 materials, 17 prices, 4 voucher codes.

### `tooth` — FDI / ISO 3950

52 static rows, generated rather than typed. Two digits: quadrant, then position
from the midline. `46` is the lower right first molar. **Left and right are the
patient's**, not the viewer's.

Five CHECK constraints keep the table self-consistent: the code must equal
`quadrant || position`; permanent teeth live in quadrants 1–4 and primary in
5–8; primary teeth stop at position 5; `is_anterior` must equal `position <= 3`;
and `valid_surfaces` must be `MIDBL` for anterior teeth and `MODBL` for
posterior. An occlusal surface on an incisor is rejected by the schema.

`universal_code` cross-references US 1–32 / A–T numbering, for imaging and CBCT
software that does not speak FDI.

### Pricing

`price_list.material_option_id` NULL is the **category base price**; a value
prices that specific material. Resolution prefers a material's own row and falls
back to the base, so a new material never requires repricing everything.

> **A plain `UNIQUE(service, material, date)` does not work here.** SQL treats
> NULLs as distinct, so two base-price rows for the same service and date would
> both be accepted. Two partial unique indexes close it:
> `uq_price_base` (WHERE material IS NULL) and `uq_price_material`
> (WHERE material IS NOT NULL). Verified by negative test.

### VAT is per service

Only `Teeth Whitening` carries VAT (10%) in the seed — cosmetic rather than
medical. Vietnamese VAT does not treat all dentistry alike. **Confirm the actual
rates with the clinic's accountant**; the schema models the shape, not the
figures.

### Views

| View | Answers |
|------|---------|
| `v_current_price` | Price in force today per service and material, with the base fallback applied |
| `v_promotion_status` | Which voucher codes are redeemable, expired, or not yet open |
| `v_bookable_chair` | The chair list a booking screen works from |

### What the seed exercises

| Case | Rows |
|------|------|
| **Superseded price** | Crown base is 5,500,000 from 2025 and 6,000,000 from 2026. Both survive, so a 2025 invoice still reprices correctly |
| **Material fallback** | Zirconia and PFM have their own prices; **E-max has none** and resolves to the base |
| **Per-service VAT** | Whitening at 10%, everything else at 0 |
| **Chair out of service** | `Ghế chỉnh nha` is under Maintenance and must not be bookable |
| **Chair requirement** | Implant and extraction need the Surgical position; a scale needs any chair |
| **Voucher states** | `TET2026` expired, `ISHD` and `WELCOME` capped, `XASH` uncapped |
| **Case-insensitive codes** | `xash` is rejected as a duplicate of `XASH` |

### Verification

`integrity_check` ok, `foreign_key_check` zero rows, all 52 FDI codes present
with no missing or extra, and **16 negative tests** proving each constraint
rejects bad data — tooth coherence, duplicate base and material prices, negative
prices, a percentage over 100, a reversed date window, a case-variant code, and
services whose scope contradicts their pricing basis.


---

## Module 3 — Scheduling

7 availability blocks, 8 appointments, 4 views, 5 triggers.

### `appointment.person_id` points at `app_user`, not `patient_profile`

An online booking happens *before* the person has arrived and become a patient,
so the appointment must be able to reference a `Provisional` person. Two of the
seeded appointments do exactly that. Conversion on arrival is then one `UPDATE`
plus one `INSERT` — this foreign key never changes, because it was valid from
the moment the booking was taken.

What was *done* at a visit is not here either. A visit routinely covers more
than one procedure, so the work is a list of `procedure_session` rows pointing
back at the appointment. That arrives with module 5.

### Triggers, because SQLite has no EXCLUDE constraints

PostgreSQL would express the overlap rules as `EXCLUDE` constraints. SQLite has
none, so they live in triggers — which keeps them in the database rather than
trusting every future caller to remember.

| Trigger | Rule |
|---------|------|
| `trg_appt_chair_overlap_ins` / `_upd` | **One chair, one patient at a time.** The reason `chair` exists |
| `trg_appt_doctor_overlap_ins` | A doctor cannot be in two chairs at once |
| `trg_appt_doctor_bookable` | Only `Intern` or `Active` staff take new work — not `OnLeave`, not `Departed` |
| `trg_appt_chair_available` | A chair under `Maintenance` or `Retired` cannot be booked |

`Cancelled` and `NoShow` appointments **release their slot** — they occupy
nothing, and the seed proves a released slot can be rebooked.

### Occupancy is derived, never stored

There is no `InUse` chair status. `Available` / `Maintenance` / `Retired` are
*configuration*, set by a human and changing rarely. Occupancy is a function of
the schedule: an appointment `InProgress` with a `chair_id` already says a
patient is in that chair. `v_chair_occupancy` reads that. Stored, it would go
stale the first time anyone forgot to unset it, and could never answer "was this
chair free at 14:00 last Tuesday?"

### Views

| View | Answers |
|------|---------|
| `v_day_sheet` | Everything booked for a day, in time order |
| `v_chair_occupancy` | Who is in which chair right now |
| `v_reschedule_followup` | Booked online, never arrived, still Provisional, nothing rebooked |
| `v_appointment_off_roster` | Appointments outside the doctor's stated hours |

`v_appointment_off_roster` is **advisory, not a constraint**. An emergency should
never be blocked by the rota — but the desk should be able to see when it
happened. It currently flags `ap-04`: Dr Quỳnh works Tuesdays and Wednesdays,
and 2026-09-05 is a Saturday.

### What the seed exercises

| Case | Rows |
|------|------|
| **Parallel capacity** | `ap-01` and `ap-02` share 2026-08-25 09:00 in *different* chairs with *different* doctors — nothing objects |
| **Provisional holds a booking** | `ap-04`, self-booked online, `created_by` NULL, person not yet a patient |
| **The reschedule chase** | `ap-03` — a Provisional no-show. Bùi Thị Hạnh is correctly *excluded*: she no-showed nothing and has a future booking |
| **Live occupancy** | `ap-07` is `InProgress`, so Ghế 1 reads "in use" |
| **Released slot** | `ap-08` is `Cancelled`; its chair and time can be rebooked |
| **Receptionist KPI credit** | `ap-05` and `ap-06` carry `followed_up_by` |
| **One-off override** | `ds-07` closes Dr Minh's National Day |

### Verification

`integrity_check` ok, `foreign_key_check` zero rows, **12 negative tests** all
rejecting and **6 positive controls** all accepted.

The chair constraint was isolated deliberately: a first attempt tripped the
*doctor* trigger instead, because the test picked a doctor who was already
booked. Rerun with a genuinely free doctor, the same chair and time is rejected
while a different chair at the same doctor and time is accepted — proving the
chair was the only conflict.

### A note on module 1

Module 1 gained a second `Active` doctor (Lâm Thị Quỳnh). With only one bookable
doctor, two appointments in one chair would always trip the doctor-overlap rule
first, and the chair constraint could never be tested in isolation.


---

## Module 4 — Treatment Planning

5 plans, 11 procedures, 35 decisions, 3 instruction templates, 3 proposals.

### The circular dependency, and what actually works

`treatment_procedure.remedy_for_failure_id` points at `treatment_failure`
(module 6), which points back. The build plan originally said to declare the
forward FK here and leave it NULL. **That does not work.** `CREATE TABLE`
accepts a forward reference, but with `PRAGMA foreign_keys = ON` the first
`INSERT` fails — *even inserting NULL*:

```sql
CREATE TABLE tp (id TEXT PRIMARY KEY, fk TEXT REFERENCES tf(id));  -- succeeds
INSERT INTO tp VALUES ('p1', NULL);        -- Error: no such table: main.tf
```

Disabling foreign keys to get past it would defeat the point. So **module 4 does
not create the column at all**, and module 6 adds it once the parent exists:

```sql
ALTER TABLE treatment_procedure
    ADD COLUMN remedy_for_failure_id TEXT REFERENCES treatment_failure(id);
```

SQLite permits a `REFERENCES` clause on `ADD COLUMN`, and it enforces normally
afterwards — verified: a valid value is accepted, an invalid one rejected, and
`foreign_key_check` stays clean. `Design/build-plan.md` has been corrected.

### The decision log is the source of truth

Nothing sets `treatment_procedure.status` directly. Every procedure is created
`Proposed` and walked to its present state by `procedure_decision` rows, with
triggers enforcing the whole discipline:

| Trigger | Rule |
|---------|------|
| `trg_decision_no_update` / `_no_delete` | The log is **append-only**. An error is corrected by a further decision, never by rewriting one |
| `trg_decision_chain` | `from_status` must match where the procedure actually is, so the log is a coherent chain rather than disconnected claims |
| `trg_decision_chain` | Only clinically meaningful transitions. `Proposed -> Completed` skips consent and is refused |
| `trg_decision_applies` | `treatment_procedure.status` is a **cache** of the log's head, updated automatically |

Legal transitions, including re-proposal after a refusal:

```
NULL -> Proposed -> Accepted -> Scheduled -> InProgress -> Completed
          |  ^
          v  |
       Declined        (and Skipped from most states)
```

### Views

| View | Answers |
|------|---------|
| `v_plan_detail` | Every plan with its procedures, materials and statuses |
| `v_procedure_trail` | The full decision history for a procedure, in order |
| `v_pending_approvals` | Both proposal types in one manager queue |
| `v_declined_work` | Informed refusal — what was declined, why, and whether the risk was explained |

### What the seed exercises

| Case | Rows |
|------|------|
| **Informed refusal and re-proposal** | `pr-09` — declined on cost with the risk explained, **re-proposed two months later**, then accepted. All four decisions survive. A `declined_at` column would have overwritten the refusal |
| **Blocked on approval** | `tp-02` sits `PendingApproval`; its braces stay `Proposed` while `sp-02` waits on the manager |
| **Staff as patient** | `tp-05` — Dr Minh treated by Dr Quỳnh, which will earn him nothing in module 8 |
| **No prices anywhere** | All 11 procedures have `unit_price` NULL: nothing has been invoiced, so no price has bound |
| **Material rules** | Crowns and implants carry a material; consultations and scalings do not |

### Verification

`integrity_check` ok, `foreign_key_check` zero rows, **14 negative tests** all
rejecting and **3 positive controls** accepted — covering append-only
enforcement, chain coherence, the transition whitelist, refusals without a
reason, a crown given an implant's material, and proposals whose review state
contradicts their reviewer.


---

## Module 5 — Clinical Record

6 health records, 18 tooth conditions, 12 `procedure_tooth` rows, 4 media items,
6 sessions, 3 views, 5 triggers.

### `surface_combination` — validating surfaces exactly

Surfaces are written in canonical order **M · O/I · D · B · L**, so a
three-surface filling is always `MOD` and never `DOM` — one spelling per set, so
it can be compared and counted. Validating that in a trigger means walking the
string checking both *membership* and *order*, which is easy to get subtly wrong.

Instead there is a generated lookup of every canonical subset: 31 per tooth type,
**62 rows**. Surfaces are valid iff the row exists. That makes five distinct
errors fall out of one check — a surface the tooth does not have, the wrong
biting surface for its type, wrong order, a duplicate, and an unknown letter.

### Findings and procedures are many-to-many, both ways

`procedure_tooth.addresses_condition_id` carries it. Because the FK sits on the
(procedure × tooth) junction, both directions work with no third table:

| Direction | Seed case |
|-----------|-----------|
| **One finding, many procedures** | Deep caries on 36 (`tc-07`) needs a **root canal and then a crown**. Both `procedure_tooth` rows point at the same finding |
| **One procedure, many findings** | A single scaling (`pr-10`) clears calculus on **six teeth** — six rows, each addressing its own tooth's finding |

Two triggers keep it honest: a procedure cannot address another patient's
finding, nor a finding on a different tooth.

### The odontogram draws three layers, and only two are the record

| Layer | Source | Is it the record? |
|-------|--------|-------------------|
| existing | restoration-type conditions, Active | **yes** |
| finding | pathology conditions, Active | **yes** |
| planned | `procedure_tooth` on Proposed/Accepted/Scheduled work | **no** — an overlay |

`v_tooth_chart` returns all three with the layer labelled, so the UI can style
planned work differently without confusing it for a fact about the tooth.

### Corrections are new rows, never deletions

`tc-10` was charted on tooth 34 by mistake — the lesion was on 37. It is marked
`EnteredInError` and superseded by `tc-08`, **not deleted**. A trigger refuses
`DELETE` outright. The chart excludes it; the table keeps it, because a clinical
record has to show what was believed at the time.

### A sequencing note on `billable_amount`

Every seeded session has `billable_amount` **NULL**, and that is correct. The
design describes it as "the value of this session's work — its share of the
procedure total", but `treatment_procedure.unit_price` does not bind until the
procedure is **first invoiced**, which is module 6. A session completing before
then genuinely has no amount yet.

So the column is nullable and module 6 fills it as invoice lines are created.
Worth revisiting there: storing a **weight** (session 1 = 60%, session 2 = 40%)
rather than an amount would separate the clinical decision — how work splits
across visits — from the money, and would be knowable at session time.

### Views

| View | Answers |
|------|---------|
| `v_tooth_chart` | The odontogram: existing state, findings, and planned work, layered |
| `v_finding_treatment` | Each finding and every procedure addressing it |
| `v_session_log` | What happened at each visit, and who did it |

### Verification

`integrity_check` ok, `foreign_key_check` zero rows, **16 negative tests** all
rejecting and **5 positive controls** accepted — covering all five surface
failure modes, whole-tooth findings that name surfaces, deletion of a clinical
finding, cross-patient and cross-tooth finding links, a session opened on work
the patient has not accepted, and invalid JSON in `vitals`.


---

## Module 6 — Billing

4 tables, 4 views, 6 triggers, 5 invoices, 8 lines, 6 payments, 1 failure.

### The circular dependency, closed

```sql
ALTER TABLE treatment_procedure
    ADD COLUMN remedy_for_failure_id TEXT REFERENCES treatment_failure(id);
```

Module 4 could not declare this forward FK — `CREATE TABLE` accepts it but the
first `INSERT` then fails, even inserting NULL. `ADD COLUMN` may carry a
`REFERENCES` clause, and it **enforces properly**: pointing the column at a
non-existent failure is rejected by the foreign key. No pragma is ever disabled.

### VAT is charged on the discounted amount, and the schema enforces it

```sql
CONSTRAINT ck_line_vat_after_discount CHECK (
    vat_amount = CAST(ROUND((line_total - discount_amount) * vat_rate / 100.0) AS INTEGER))
```

`inv-04` is the case worth reading. Whitening at 10% VAT and a scaling at 0%,
with the `XASH` voucher taking 10% off the invoice:

| Line | Gross | Allocated discount | Net | VAT | Charge |
|------|-------|--------------------|-----|-----|--------|
| Whitening | 3,000,000 | 300,000 | 2,700,000 | 10% → 270,000 | 2,970,000 |
| Scale & polish | 500,000 | 50,000 | 450,000 | 0% → 0 | 450,000 |
| **Total** | 3,500,000 | 350,000 | 3,150,000 | **270,000** | **3,420,000** |

Charging VAT on the gross would have billed **3,450,000** — 30,000 too much on a
single visit. `v_vat_check` computes both figures side by side so the difference
is visible rather than asserted.

Invoice totals are **derived by trigger** from the lines, so `subtotal`,
`discount_amount`, `vat_total` and `total` cannot drift from what was itemised.

### The failed extraction, end to end

Tuấn returns four days after an extraction with a retained root fragment. The
manager judges it `ClinicTechnique` and orders `Both` — refund and free rework.
Three linked consequences, none of them needing new machinery:

| Step | Recorded as |
|------|-------------|
| Cancel the charge | `il-07`, an invoice line with `line_total = -1,200,000` naming `il-02` in `credits_line_id` |
| Return the money | `pay-06`, a `Payment` with `direction = Out` |
| Redo it free | `pr-13`, a procedure with `remedy_for_failure_id = tf-01` |

The invoice ends balanced at zero with **both the charge and its reversal
visible** — never edited. And `pr-13` is refused billing outright by a trigger:
free rework exists because the clinic was at fault.

### The sequencing gap from module 5 resolves here

`procedure_session.billable_amount` and `treatment_procedure.unit_price` were
NULL after module 5, because no price binds until a procedure is first invoiced.
Triggers now fill both as each invoice line is created.

### Views

| View | Answers |
|------|---------|
| `v_invoice_balance` | What is owed, netting refunds against receipts |
| `v_invoice_detail` | The itemised bill, with the tax working shown |
| `v_vat_check` | Proof the discount was allocated before VAT, per invoice |
| `v_treatment_failure` | Failed work, the judgment, and what followed |

### Four gaps found by auditing the module after it was built

The tests all passed, but reviewing what they *did not* cover turned up four
ways wrong data could still get in. All four are now closed and tested.

| Gap | What it allowed | Fix |
|-----|-----------------|-----|
| `invoice.status` was never maintained | A fully settled invoice still read `PartiallyPaid` — `inv-01` did exactly that after its refund | `trg_payment_settles` and `trg_line_resettles` recompute it whenever money or a line moves |
| `line_total` was unconstrained | `unit_price` 100 at quantity 3 was accepted as **999,999** | `ck_line_total_is_price_times_qty`, negated for a credit line |
| The discount was untied to its voucher | An invoice could name `XASH` (10%) and take **5,000,000 off 6,000,000** | `trg_invoice_issue_validates` checks the discount against the promotion's own rate |
| `pricing_basis` was never exercised | Every line was quantity 1, so `PerSurface` and `PerTooth` were untested | `inv-05` now bills a three-surface filling at **quantity 3** |

The third fix changed how invoices are built. They are now assembled as a
**Draft**, given their lines, and then **issued** — which is the moment the
figures are complete and therefore the moment to check them. Issuing also
refuses an invoice with no lines, a discount with no source, and an expired
voucher.

### Verification, and a constraint bug the tests caught

`integrity_check` ok, `foreign_key_check` zero rows, **23 negative tests** and
**3 positive controls**, plus a standing regression over six invariants: line
discounts summing to the invoice discount, every line agreeing with its own
arithmetic, VAT always on the net, free rework unbilled, no session billed
twice, and prices bound only where billing occurred.

One test failed on the first run, and the constraint was genuinely wrong:

```sql
-- WRONG
(status = 'Draft') = (number IS NULL AND serial IS NULL AND issued_at IS NULL)
```

An `Issued` invoice with `issued_at` set but **no number** passed it: the left
side is 0, and so is the right, so the equality holds. The rule only forced the
three fields to be NULL *together*; it never required them all to be *present*
once issued. Rewritten as a `CASE`, and all four numbering cases now reject
while a `Voided` invoice correctly keeps its number.


---

## Module 7 — Inventory

5 tables, 5 views, 3 triggers. 3 vendors, 8 items, 9 batches, 20 movements.

### The log is the source of truth

Nothing writes `quantity_on_hand` or `quantity_remaining` directly. Every
movement goes through `inventory_log`, and a trigger applies it to both the
batch and the item. `quantity_after` is a snapshot the caller supplies, and a
second trigger **rejects it if it does not follow** from the current level plus
the delta — so a log that lies about its own effect cannot be written.

A new batch must start at `quantity_remaining = 0` and be filled by a
`Restocked` log, rather than arriving pre-populated. That keeps one path in.

### Expiry belongs to the batch

Composite A2 is the case: **two deliveries, two expiries, two costs.**

| Lot | Expiry | Remaining | Unit cost |
|-----|--------|-----------|-----------|
| CA2-2405 | 2026-11-30 | 8 | 180,000 |
| CA2-2508 | 2027-06-30 | 20 | 210,000 |

`v_pick_order` ranks batches earliest-expiry-first, which is what stops usable
stock quietly expiring behind newer stock. The three-surface filling drew from
the **older 180,000 lot**, and `v_procedure_material_cost` reports its material
cost accordingly. Without a per-batch cost that figure would be a guess.

### The `Expired` change type finally has something to drive it

Lot `LD-2401` lidocaine expired on 2026-07-31 with 48 cartridges left —
**1,056,000 written off**, recorded as a movement rather than silently
disappearing. That enum value existed from the first design and until now
nothing could produce it.

### Two tracks, meeting at the item

`procedure_supply_list` says what a procedure *should* need — attached to a
reusable instruction template, or to one specific procedure, never both.
`inventory_log` records what it *actually* consumed. `v_supply_variance`
compares them, which is the whole reason the two are kept apart.

### Views

| View | Answers |
|------|---------|
| `v_pick_order` | FEFO: which lot to open next, and what is expiring |
| `v_low_stock` | What to reorder, and who to call |
| `v_expired_stock` | Batches past their date still holding stock, and the value at risk |
| `v_supply_variance` | Expected versus actual consumption |
| `v_procedure_material_cost` | What a procedure cost in materials, from the lots opened |

### Materials and equipment are different things

The first version put both in `inventory_item` behind a `tracks_expiry` flag.
That flag was really asking *"is this equipment?"* while phrased as a fact about
shelf life — and the correlation in the data was exact: the one item marked
untracked was the one piece of equipment.

It also left a hole. `unit_cost` lives on the batch, so an item with no batches
had **nowhere to record what it cost**. Prophy cups consumed on two procedures
reported a NULL material cost.

The two have genuinely different lifecycles:

| | Material | Equipment |
|---|----------|-----------|
| Ends by | being **consumed**, or **expiring** | **breaking**, or being **retired** |
| Kept safe by | a use-by date | being **serviced** |
| Bought as | lots, at a price per lot | an asset, at one price |
| Lifecycle | batch in, batch out | InService → UnderMaintenance → Retired |

So `inventory_item` is now **materials only** — always batched, so cost always
has a home — and `equipment` is its own table carrying `purchase_cost` directly,
with `equipment_maintenance` for its service history. `tracks_expiry` is gone;
`category` is restricted to Consumable, Medication and Lab.

Two reclassifications fell out of it:

- The **dental mirror** became equipment, alongside handpieces, the autoclave and
  a retired scaler.
- The **prophy cup** turned out to be a *material* I had mislabelled — sterile,
  single-use, consumed. It now has a lot and a shelf life like anything else,
  and its cost appears. That was the whole of the reported hole.

`equipment.status` is deliberately the same shape as `chair.status`. A chair
*is* equipment — one that happens to be bookable — and the two are kept separate
only because a chair's primary role is scheduling capacity.

`v_equipment_status` reports what is in service, what is away for repair, and
what is **overdue a service** — the equipment equivalent of an expiry alert.

### Verification

`integrity_check` ok, `foreign_key_check` zero rows, **26 negative tests** all
rejecting and **6 positive controls** accepted — covering a tracked item moved
without naming its lot, an untracked item given one, a batch from the wrong
item, a false `quantity_after`, consumption beyond what a batch or item holds,
every change type moving stock the wrong way, a zero movement, a pre-filled
batch, a duplicate lot number, and supply lists owned by both or neither parent.

A standing regression now runs across all seven modules: stock reconciles to
batch remainders, no expired stock was ever consumed, all consumption sits on
work that actually started, no batch was born expired, invoice arithmetic holds,
VAT is always on the net, and every procedure's status equals the head of its
decision log.


---

## Module 8 — Payroll & Commission

Seven tables answering two different questions that happen to settle into the
same payslip: *what were you paid for your time* and *what did you earn from the
work you did*.

### Time is priced on the day it was worked, not the day it is paid

`wage_rate` is versioned, never overwritten — a new rate is a new row with an
`effective_from`, and the old one stays. Pricing a day resolves the greatest
`effective_from` that is ≤ that day, so a raise applies forward and never
rewrites history.

The seed makes this concrete. The assistant started on a trainee rate of 45,000
and was reviewed up to 55,000 on 16 August:

| Date | Hours | Rate that day | Pay |
|------|-------|---------------|-----|
| 3–5 Aug | 8.0 each | 45,000 | 360,000 each |
| 18 Aug onward | 8.0 each | 55,000 | 440,000 each |

`v_attendance_priced` sums August to **3,252,500 over 63.5 hours**, which is
exactly the `base_pay` on the payslip. Had the rate been read as "current", the
same August would have come out 635,000 too high. This is the thing that had to
work: hours worked as an Intern keep their Intern price after promotion.

Only the assistant clocks in — everyone else is `Monthly`, so `hours` on their
payslip is 0 and `base_pay` is the monthly rate. `v_payslip` handles both
without a branch in the application.

### Commission follows the work, and only the work

`commission_entry` is the single money row for every kind of earning — a
completed clinical session, or a receptionist event. Four triggers guard it, and
they are what the module is really for:

| Trigger | Refuses |
|---------|---------|
| `trg_ce_not_own_treatment` | earning on a session whose **patient is you** |
| `trg_ce_must_have_worked` | crediting anyone who was not the session's performer or assistant; a session that is not `Completed`; free rework |
| `trg_ce_amount_matches_rule` | an amount that is not what the cited rule grants |
| `trg_ce_base_is_session_value` | a base that is not the session's own `billable_amount` |

The first is the rule the design has carried since the beginning — *a doctor
cannot earn commission on their own treatment* — and the seed exercises it for
real rather than asserting it. Dr Minh is a patient at his own clinic
(`tp-05`); Dr Quỳnh whitened and scaled his teeth with Đỗ Văn Nam assisting:

| Session | Paid to | Base | Amount |
|---------|---------|------|--------|
| ps-07 | Lâm Thị Quỳnh | 3,000,000 | 450,000 |
| ps-07 | Đỗ Văn Nam | 3,000,000 | 150,000 |
| ps-08 | Lâm Thị Quỳnh | 500,000 | 75,000 |
| ps-08 | Đỗ Văn Nam | 500,000 | 25,000 |

Dr Minh earns **nothing** on either — not because the seed omits him, but
because the insert is refused. The same two rows also show a doctor and an
assistant paid on one session at their own separate rates, which is the normal
case.

### Which rule applies, when three could

`commission_rule` is scoped three ways and resolved most-specific-first:

| Precedence | Rule | Scope | Rate |
|---|------|-------|------|
| 1 | `cr-04` | Dr Minh, on implants (his contract) | 22% |
| 2 | `cr-03` | anyone, on implants | 20% |
| 3 | `cr-01` | any doctor, any service | 15% |

The contract rate beats the category rate beats the role rate. Rules are
versioned by `effective_from` exactly as wages are, and an entry citing a rule
that was **not yet in force** when it was earned is refused.

Scope is mutually exclusive by CHECK: clinical roles are scoped by service
category, the receptionist by `event_type`, never both.

### The receptionist earns on events, not on money

`receptionist_performance_log` records *what happened* — this receptionist
brought in this patient — and stays separate from the payment. The seed carries
two `NewPatientRegistered` and one `SuccessfulFollowUp`, each paying a
`FixedAmount`, which is why the receptionist's dashboard rows show a
`total_base` of 0: there is no invoice underneath them, and there should not be.
Keeping the event log apart from the money is what lets the manager change the
per-event bounty later without rewriting history.

### The manager's chargeback, end to end

`payroll_adjustment` is where a manager charges a loss back to the staff member
who caused it. The failed extraction from module 6 (`tf-01`, retained root
fragment) produced a refund; the debit follows:

    Trần Văn Minh   DEBIT   −1,500,000   "Retained root fragment at extraction
                                          of #46 (tf-01). Clinic refunded…"

It sits in `v_unsettled` alongside a 500,000 credit to the assistant for weekend
cover — both waiting for the September run, both requiring a written reason.
`ck_adj_reason` refuses a blank one, because an unexplained deduction from
someone's pay is exactly the thing an audit will ask about.

Note that the *free rework* on the same failure earns no commission either —
`trg_ce_must_have_worked` checks `remedy_for_failure_id`. The clinic absorbs the
cost once, not twice.

### Nothing settled can be edited

Three triggers close the books: an **approved** `payroll_record` cannot be
changed, and a **settled** `commission_entry` or `payroll_adjustment` cannot be
either. Corrections go in as a new adjustment in the next period, the same
append-only discipline used by `procedure_decision` and `invoice_line`.

`ck_payroll_math` holds `net_pay = base_pay + commission_total + total_credits −
total_debits` at the row level, and `(status = 'Pending') = (payroll_record_id
IS NULL)` keeps an entry from claiming to be both unsettled and already paid.

### Views

| View | Answers |
|------|---------|
| `v_current_wage` | What each staff member is paid *now* |
| `v_attendance_priced` | Each shift at the rate in force that day |
| `v_commission_dashboard` | **Manager only** — earnings per staff member, by settlement status |
| `v_commission_detail` | Line by line: which session, which rule, how much |
| `v_payslip` | The August run: hours, base, commission, credits, debits, net |
| `v_unsettled` | What the next run owes and claws back |

### Eighteen gaps found by auditing the module after it was built

The first 14 negative tests all passed, and proved less than they looked. Asking
the other question — *what would still get through?* — found eighteen holes. The
seed itself was clean: every total reconciled, every entry cited a rule matching
its holder's role, and rule precedence resolved correctly in the data. What was
missing was anything **making** that true.

**1. Every guard was BEFORE INSERT, so UPDATE walked past all of them.** A clean
entry could be written and then edited onto another session, another person, or
another amount. `total_minutes` — the quantity the whole wage is multiplied by —
could simply be typed over. Closed with `trg_ce_facts_immutable` (an entry
records work done; only its settlement may change), an UPDATE twin of the
minutes check, and `trg_att_locked_once_settled`. A Pending entry entered by
mistake is *deleted* and rewritten; one already paid is clawed back with an
adjustment.

**2. Rule precedence was a comment, not a constraint.** The three-level
resolution documented above `commission_rule` existed only in prose: nothing
tied an entry to the rule that actually applied. All four of these were
accepted —

| Accepted before | Should have been |
|-----------------|------------------|
| assistant paid on the doctor's 15% | his own 5% — **360,000 instead of 120,000** |
| Dr Quỳnh billing Dr Minh's personal 22% contract | the 20% she is entitled to |
| a composite filling paid at the implant rate | the 15% catch-all |
| a doctor citing the receptionist's fixed bounty | not a rule available to him at all |

`trg_ce_cites_the_applicable_rule` now runs the documented resolution — contract
rate, then category rate, then role catch-all — and refuses any entry citing
anything else. The comment and the schema finally say the same thing.

**3. Payroll totals did not have to follow from their rows.** `ck_pay_net` only
checked that the figures were internally consistent; a record claiming
`base_pay` of 99,000,000 with no attendance behind it was accepted *and
approvable*. This is the module 6 `line_total` gap in a new place, and it is
closed the same way: `trg_payroll_approval_validates` recomputes base pay from
the wage in force, hours from the attendance linked, commission from the entries
linked, and credits and debits from the adjustments linked — **at the moment of
approval**, which is when a draft becomes a promise to pay.

That forced the seed to be restructured into the three steps a real run takes:
open the record as a Draft, gather the month's rows into it, then approve and
pay. A record inserted straight into `Paid`, as the first version did, would
never pass the gate that matters.

**4. Settlement did not check whose payslip it was.** One staff member's
commission could be settled into another's payroll record, and September's
commission into the August run. Worse, the first fix only guarded INSERT — and
settlement is an **UPDATE**, so the check never fired in practice. That was
caught not by a negative test but by a *positive* one: running a September
payroll end to end and asking whether the manager's chargeback against one
dentist could land on the assistant's payslip. It could.

**5. Attendance had no overlap rule.** `UNIQUE(staff, date, clock_in)` only
stopped an identical clock-in; 08:00–16:00 and 09:00–17:00 both stood and both
were paid. `date` could also disagree with `clock_in`, which would price the
shift at some other day's rate — and a **monthly-salaried** manager could clock
in and be paid their monthly rate *per hour*.

The overlap trigger's first version treated an open shift as running to the end
of time. That correctly refused a second clock-in, but a positive control showed
what else it refused: one forgotten clock-out locked that staff member out of
the log *permanently* — they could never record another shift. An open shift is
now bounded at the end of its own day, and a partial **unique** index on
`(staff_id) WHERE clock_out IS NULL` is what enforces one open shift at a time.
Both directions now hold: a night shift crossing midnight and tomorrow's shift
are accepted; overlapping shifts and a double clock-in are not.

**6. The receptionist's uniqueness was wrong in both directions.** The UNIQUE
spanned `appointment_id`, and SQLite treats NULLs as distinct — so the same
registration logged twice with no appointment was two rows, and paid twice. The
uniqueness is genuinely different per event type, and now says so: a patient is
registered new exactly **once**; a follow-up is unique to the **appointment** it
brought them back for, and requires one. Nothing checked the logger was a
receptionist, either.

**7. `ck_pay_approved` had the same hole as `ck_inv_number_only_when_issued`.**
Written as an equality, a `Paid` record with an `approved_at` but **no approver**
passed — both sides were simply false. Rewritten as a `CASE`, exactly as in
module 6. The same shape of bug, in the same shape of constraint, two modules
apart.

### The contract rate, proven

`cr-04` — Dr Minh's personal 22% on implants — had no row exercising it, because
the seed's only implant (`pr-03`) is still `Scheduled`. That state is worth
keeping: it is the one procedure showing *accepted and booked but not yet done*.
So the rate is proven by test instead, completing `ps-03` inside a rolled-back
transaction:

| Claim | Result |
|-------|--------|
| Dr Minh at his contract 22% = 5,500,000 | **accepted** — the rule that applies |
| the same work at the role's implant 20% | rejected |
| the same work at the 15% catch-all | rejected |
| Dr Quỳnh placing it, at 20% | **accepted** — she has no contract rate |
| Dr Quỳnh claiming Dr Minh's 22% | rejected |
| the assistant on that implant, 5% | **accepted** |

### Verification

`integrity_check` ok, `foreign_key_check` zero rows, **24 negative tests** all
rejecting and **10 positive controls** accepted.

Two lessons repeated from earlier modules. First, a rejection is only evidence
once you know *which* rule rejected it: the four wrong-rule tests all "passed"
on the first run, and every one had tripped a different trigger — two on "did
not work this session" because the staff member picked had not worked it, one on
the duplicate index. Rerun against the real workers, all four were accepted.
Second, the positive controls earned their place — two of the eighteen holes
(settlement by UPDATE, and the lockout from a forgotten clock-out) were found by
asking what the new constraints wrongly *refused*, not what they let through.

Seven August payslips reconcile, and the standing regression now spans all eight
modules — payslip arithmetic, approved totals matching the rows behind them,
commission equals base × rule rate, every entry citing its own role's rule,
nobody paid on their own treatment, commission only to the worker, free rework
earning nothing, settlement landing on its own record, no overlapping shifts,
plus the module 6 and 7 checks.

### A prerequisite this module exposed in module 6

Commission is computed from `procedure_session.billable_amount`, and an
**Upfront** invoice bills the *procedure*, not the session — so `ps-04`'s
sessions had no value and could never have earned anything. Fixed at the source:
`trg_line_binds_procedure_price` now spreads the procedure's charge across its
planned sessions when the line is written. Two stale appointment statuses
(`ap-06`, `ap-07`) were corrected at the same time.

---

## Module 9 — Notifications

One table. It records **what should be sent, to whom, and about what** —
delivery is out of scope by decision, and stays that way: getting a message onto
a phone is a separate system (internal chat, SMS, Zalo) that will bring its own
channel, delivery status and retry policy. Those columns belong with that
adapter.

What is left after removing delivery is not trivial, though. Three things had to
be right.

### The pointer is polymorphic, so it is enforced by trigger

A notification is almost always *about* something — an appointment, an invoice,
a failed treatment, a payslip. That reference cannot be a foreign key, because
it points at eight different tables. Left unchecked, a notification could claim
to be about `inv-99` and the UI would render an empty page with no sign anything
was wrong.

`related_entity_type` is restricted to eight names, both halves of the pointer
are required together, and `trg_notif_target_exists` checks the row is really
there — one explicit clause per type, since SQLite cannot resolve a table name
at runtime. `v_notification_context` then resolves each link to a human label,
and because every link is guaranteed to go somewhere, that label is never blank:

| | |
|---|---|
| `Appointment` `ap-03` | appointment 2026-08-20 10:00:00 (NoShow) |
| `Invoice` `inv-05` | invoice PartiallyPaid, total 2160000 |
| `InventoryItem` `it-comp-a2` | Composite A2, 28 syringe on hand |
| `PayrollRecord` `pay-2608-ast01` | payslip 2026-08-01 to 2026-08-31 |

### A broadcast is delivered by profile, never by role

`v_inbox` is the query the inbox is built from: your own messages, plus every
broadcast that reaches you. The first version joined `n.recipient_role = u.role`
— which is precisely the mistake module 1's own header warns against, *portal
access is granted by profile, never by role* — and it broke in both directions:

- a **departed** doctor and one **on leave** both received the staff
  announcement about implant contract rates, though neither can open the staff
  portal at all;
- the clinic-closure notice to Patients **missed the two doctors who are
  themselves patients here**, and instead reached two provisional people who
  booked online, never arrived, and have no patient record.

Now staff broadcasts go to staff whose `employment_status` is `Intern` or
`Active`, and patient broadcasts to everyone holding a `patient_profile`,
whatever their role says. Ngô Bảo Châu — departed staff, still a patient here —
receives the clinic notice and not the staff one, which is the *"a staff member
who quits can still be a patient"* rule from module 1 finally visible in a
query.

### A patient may only be told about their own care

Nothing enforced this, and the seed proved within minutes why it mattered.
`v_pending_chases` lists the no-show reschedules and outstanding balances that
have no notification yet — and it named **different people** than the
notifications had been addressed to:

| Notification | Sent to | Actually concerns |
|---|---|---|
| no-show reschedule, `ap-03` | Bùi Thị Hạnh | **Ngô Quang Huy** |
| balance outstanding, `inv-05` | Lý Văn Hùng | **Phạm Thị Ngọc** |

Two live defects, each one handing a patient another patient's information.
`trg_notif_patient_sees_own` now refuses them. Staff are exempt — being told
about other people's appointments is the job — which is why the receptionist can
still page a doctor about a waiting patient, and why Dr Minh, who is both, is
told about his own plan without trouble.

That trigger is `BEFORE INSERT` only, and for once by design rather than
omission: recipient and target are both frozen by
`trg_notif_content_immutable`, so no later UPDATE can break the rule.

### Smaller rules worth stating

- **You page a person, never a role** — a page everyone receives is one nobody
  answers. An announcement is the opposite, and must be a broadcast.
- **A broadcast cannot be marked read.** There is no single reader to read it.
  Per-recipient read state needs a row per recipient and arrives with the
  delivery system; until then a broadcast stays unread by construction.
- **Read state uses a `CASE`, not an equality** — the shape that hid a bug in
  module 6 and again in module 8. Written as an equality, a row with *both*
  `is_read = 0` and a `read_at` would pass.
- **Marking read goes one way**; a sent message's content never changes at all.
- **Nobody who has left is paged to the floor**, though they may still hear from
  the clinic as a patient.

### Views

| View | Answers |
|------|---------|
| `v_inbox` | What each person actually sees — direct messages plus broadcasts that reach them |
| `v_unread_count` | The badge number, per person |
| `v_notification_context` | Each polymorphic link resolved to something readable |
| `v_pending_chases` | No-shows and outstanding balances with no notification raised yet |

### Verification

`integrity_check` ok, `foreign_key_check` zero rows, **22 negative tests** all
rejecting and **6 positive controls** accepted — covering a dangling pointer, an
appointment id in the invoice slot, half a pointer either way, a message to
nobody or to both a person and a role, a broadcast page, a direct announcement,
self-notification, every incoherent read state, un-reading, rewriting or
redirecting a sent message, and paging someone who has left.

`v_pending_chases` is empty in the seed, which is the correct answer — both
chases were raised — so it is proven by withdrawing the two notifications inside
a rolled-back transaction and watching the no-show and the outstanding balance
reappear.

The standing regression now spans all nine modules: every notification link
resolves, no patient sees another's care, no broadcast reaches a leaver, read
state is coherent, plus the payroll, billing, inventory and clinical checks from
modules 5 through 8.
