# KPX Database

Built one module at a time, following `Design/build-plan.md`.
`Design/core-entities/entities.md` is the source of truth for the model.

**Status: module 1 of 9 complete.**

| # | Module | Entities | Built |
|---|--------|----------|-------|
| 1 | People & Access | app_user, staff_profile, patient_profile | ✅ |
| 2 | Clinic Setup | tooth, chair_type, chair, service_category, material_option, price_list, promotion | — |
| 3 | Scheduling | doctor_schedule, appointment | — |
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

Drops `kpx.db` and replays every file in `db/modules/` in order. The `.db` is a
build artefact and is gitignored; the `.sql` files are the source of truth.

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
