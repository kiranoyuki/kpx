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
| 7 | Inventory | vendor, inventory_item, inventory_batch, inventory_log, procedure_supply_list | ✅ |
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

### A gap worth deciding on

**Untracked items have no cost basis.** `unit_cost` lives on the batch, and an
item with `tracks_expiry = 0` has no batches — so a prophy cup consumed on two
procedures reports a NULL cost. Cheap consumables, so arguably immaterial, but
it is currently *silent* rather than *decided*. If the accountant's cost
reporting needs them, `inventory_item` would want its own `unit_cost` for the
untracked case.

### Verification

`integrity_check` ok, `foreign_key_check` zero rows, **15 negative tests** all
rejecting and **4 positive controls** accepted — covering a tracked item moved
without naming its lot, an untracked item given one, a batch from the wrong
item, a false `quantity_after`, consumption beyond what a batch or item holds,
every change type moving stock the wrong way, a zero movement, a pre-filled
batch, a duplicate lot number, and supply lists owned by both or neither parent.

Stock levels were also reconciled: for every tracked item, `quantity_on_hand`
equals the sum of its batches' `quantity_remaining`.
