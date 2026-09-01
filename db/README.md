# KPX Database

Built one module at a time, following `Design/build-plan.md`.
`Design/core-entities/entities.md` is the source of truth for the model.

**Status: modules 1–3 of 9 complete.**

| # | Module | Entities | Built |
|---|--------|----------|-------|
| 1 | People & Access | app_user, staff_profile, patient_profile | ✅ |
| 2 | Clinic Setup | tooth, chair_type, chair, service_category, material_option, price_list, promotion | ✅ |
| 3 | Scheduling | doctor_schedule, appointment | ✅ |
| 4 | Treatment Planning | treatment_plan, procedure_instruction, treatment_procedure, procedure_decision, discount_proposal, special_procedure_proposal | — |
| 5 | Clinical Record | health_record, tooth_condition, procedure_tooth, patient_media, procedure_session | — |
| 6 | Billing | invoice, invoice_line, payment, treatment_failure | — |
| 7 | Inventory | vendor, inventory_item, inventory_batch, inventory_log, procedure_supply_list | — |
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
