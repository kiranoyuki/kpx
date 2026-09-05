# KPX — Rule Catalogue

> Every rule the database enforced procedurally, captured **before** the triggers were
> removed, plus any rule added since that would have been a trigger had one existed.
> This is the specification the API implements, and the test plan for it.
>
> Declarative constraints are **not** listed here — 176 CHECK, 108 foreign keys and 35
> unique constraints stay in the schema and continue to be enforced by SQLite. This
> document covers only what the API now has to own.

**How to read the third column.** A `CHECK` constraint can only see the row being
written. Every rule below needed to look somewhere else, which is why none of them
could be declarative, and why each one now becomes application code. Where it reads
`—`, the rule is enforced simply by the API exposing no such operation.

| # | Rule | Needs to look at | Message to the user |
|---|------|------------------|---------------------|
| 1 | `trg_appt_chair_available` <br> *before insert on* `appointment` | chair | chair is not Available |
| 2 | `trg_appt_chair_overlap_ins` <br> *before insert on* `appointment` | other appointment rows | chair double-booked: another appointment overlaps this chair |
| 3 | `trg_appt_chair_overlap_upd` <br> *before update on* `appointment` | other appointment rows | chair double-booked: another appointment overlaps this chair |
| 4 | `trg_appt_doctor_bookable` (1/2) <br> *before insert on* `appointment` | staff_profile | doctor is not currently bookable (OnLeave or Departed) |
| 5 | `trg_appt_doctor_bookable` (2/2) <br> *before insert on* `appointment` | staff_profile | assistant is not currently bookable (OnLeave or Departed) |
| 6 | `trg_appt_doctor_overlap_ins` <br> *before insert on* `appointment` | other appointment rows | doctor double-booked: another appointment overlaps this doctor |
| 7 | `trg_decision_applies` <br> *after insert on* `procedure_decision` | derives treatment_procedure.status | *derived value — no refusal* |
| 8 | `trg_decision_chain` (1/3) <br> *before insert on* `procedure_decision` | earlier procedure_decision rows | from_status does not match the procedure's current status |
| 9 | `trg_decision_chain` (2/3) <br> *before insert on* `procedure_decision` | earlier procedure_decision rows | decided_at is earlier than the previous decision on this procedure |
| 10 | `trg_decision_chain` (3/3) <br> *before insert on* `procedure_decision` | earlier procedure_decision rows | illegal status transition |
| 11 | `trg_decision_no_delete` <br> *before delete on* `procedure_decision` | —  (no delete path in the API) | procedure_decision is append-only: it cannot be deleted |
| 12 | `trg_decision_no_update` <br> *before update on* `procedure_decision` | —  (no update path in the API) | procedure_decision is append-only: it cannot be updated |
| 13 | `trg_proc_material_required` (1/2) <br> *before insert on* `treatment_procedure` | service_category, material_option | this service requires a material choice |
| 14 | `trg_proc_material_required` (2/2) <br> *before insert on* `treatment_procedure` | service_category, material_option | material does not belong to this service category |
| 15 | `trg_cond_no_delete` <br> *before delete on* `tooth_condition` | —  (no delete path) | tooth_condition is append-only: mark it EnteredInError instead |
| 16 | `trg_cond_surfaces_valid` <br> *before insert on* `tooth_condition` | tooth | surfaces are not a canonical subset of this tooth's valid surfaces |
| 17 | `trg_ptooth_condition_same_patient` (1/2) <br> *before insert on* `procedure_tooth` | tooth_condition, treatment_plan | that finding belongs to a different patient |
| 18 | `trg_ptooth_condition_same_patient` (2/2) <br> *before insert on* `procedure_tooth` | tooth_condition, treatment_plan | that finding is on a different tooth |
| 19 | `trg_ptooth_surfaces_valid` <br> *before insert on* `procedure_tooth` | tooth | surfaces are not a canonical subset of this tooth's valid surfaces |
| 20 | `trg_session_needs_accepted` <br> *before insert on* `procedure_session` | treatment_procedure | cannot open a session on a procedure that is not at least Accepted |
| 21 | `trg_invoice_issue_validates` (1/4) <br> *before update on* `invoice` | invoice_line rows | cannot issue an invoice with no lines |
| 22 | `trg_invoice_issue_validates` (2/4) <br> *before update on* `invoice` | invoice_line rows | discount does not match the promotion rate |
| 23 | `trg_invoice_issue_validates` (3/4) <br> *before update on* `invoice` | invoice_line rows | promotion is not redeemable on the invoice date |
| 24 | `trg_invoice_issue_validates` (4/4) <br> *before update on* `invoice` | invoice_line rows | a discount needs a source: a voucher or an approved proposal |
| 25 | `trg_invoice_totals_ins` <br> *after insert on* `invoice_line` | derives invoice subtotal/vat/total | *derived value — no refusal* |
| 26 | `trg_line_billable_source` (1/3) <br> *before insert on* `invoice_line` | treatment_procedure, procedure_session | only a Completed session may be billed |
| 27 | `trg_line_billable_source` (2/3) <br> *before insert on* `invoice_line` | treatment_procedure, procedure_session | a Declined or Proposed procedure can never be billed |
| 28 | `trg_line_billable_source` (3/3) <br> *before insert on* `invoice_line` | treatment_procedure, procedure_session | free rework is non-billable: it exists because the clinic was at fault |
| 29 | `trg_line_binds_procedure_price` <br> *after insert on* `invoice_line` | derives unit_price and billable_amount | *derived value — no refusal* |
| 30 | `trg_line_immutable_once_issued` <br> *before update on* `invoice_line` | invoice.status | invoice lines are immutable once the invoice leaves Draft |
| 31 | `trg_line_resettles` <br> *after insert on* `invoice_line` | derives invoice totals after a credit | *derived value — no refusal* |
| 32 | `trg_line_settles_session` <br> *after insert on* `invoice_line` | derives procedure_session billed state | *derived value — no refusal* |
| 33 | `trg_payment_settles` <br> *after insert on* `payment` | derives invoice.status | *derived value — no refusal* |
| 34 | `trg_refund_needs_determination` <br> *before insert on* `payment` | treatment_failure, invoice_line | a refund requires a credit line on this invoice |
| 35 | `trg_batch_starts_empty` <br> *before insert on* `inventory_batch` | —  (single row) | a new batch starts with quantity_remaining = 0; record a Restocked log to fill it |
| 36 | `trg_log_applies` <br> *after insert on* `inventory_log` | derives quantity_on_hand and quantity_remaining | *derived value — no refusal* |
| 37 | `trg_log_batch_required` (1/2) <br> *before insert on* `inventory_log` | inventory_item | that batch belongs to a different item |
| 38 | `trg_log_batch_required` (2/2) <br> *before insert on* `inventory_log` | inventory_item | quantity_after does not match quantity_on_hand + quantity_delta |
| 39 | `trg_log_fefo` <br> *before insert on* `inventory_log` | other inventory_batch rows | an older unexpired lot still has stock: FEFO requires opening that one first |
| 40 | `trg_log_no_expired_consumption` <br> *before insert on* `inventory_log` | inventory_batch.expiry_date | that lot has expired: it must be written off, not used |
| 41 | `trg_log_procedure_must_have_started` <br> *before insert on* `inventory_log` | treatment_procedure | that procedure has not started: it cannot have consumed anything |
| 42 | `trg_log_procedure_must_have_started_upd` <br> *before update of related_procedure_id on* `inventory_log` | treatment_procedure | that procedure has not started: it cannot have consumed anything |
| 43 | `trg_adj_locked_once_settled` <br> *before update on* `payroll_adjustment` | —  (no edit path once settled) | a settled adjustment is immutable: raise an offsetting one instead |
| 44 | `trg_adj_settles_into_own_record` (1/2) <br> *before insert on* `payroll_adjustment` | payroll_record | that payroll record belongs to a different staff member |
| 45 | `trg_adj_settles_into_own_record` (2/2) <br> *before insert on* `payroll_adjustment` | payroll_record | that adjustment was raised after this pay period closed |
| 46 | `trg_adj_settles_into_own_record_upd` (1/2) <br> *before update on* `payroll_adjustment` | payroll_record | that payroll record belongs to a different staff member |
| 47 | `trg_adj_settles_into_own_record_upd` (2/2) <br> *before update on* `payroll_adjustment` | payroll_record | that adjustment was raised after this pay period closed |
| 48 | `trg_att_hourly_only` <br> *before insert on* `attendance_log` | wage_rate | attendance prices hourly wages: this staff member is not on one |
| 49 | `trg_att_locked_once_settled` <br> *before update on* `attendance_log` | —  (no edit path once paid) | this shift has already been paid: correct it with an adjustment |
| 50 | `trg_att_minutes_match` <br> *before insert on* `attendance_log` | —  (single row) | total_minutes does not match clock_in and clock_out |
| 51 | `trg_att_minutes_match_upd` <br> *before update on* `attendance_log` | —  (single row) | total_minutes does not match clock_in and clock_out |
| 52 | `trg_att_no_overlap` <br> *before insert on* `attendance_log` | other attendance_log rows | that shift overlaps one already logged for this staff member |
| 53 | `trg_ce_amount_matches_rule` (1/2) <br> *before insert on* `commission_entry` | commission_rule | commission amount does not match the rule it cites |
| 54 | `trg_ce_amount_matches_rule` (2/2) <br> *before insert on* `commission_entry` | commission_rule | that rule was not yet in force when the commission was earned |
| 55 | `trg_ce_base_is_session_value` <br> *before insert on* `commission_entry` | procedure_session | commission_base must equal the session's billable_amount |
| 56 | `trg_ce_cites_the_applicable_rule` <br> *before insert on* `commission_entry` | commission_rule (precedence) | that is not the rule that applies to this staff member and this work |
| 57 | `trg_ce_facts_immutable` <br> *before update on* `commission_entry` | —  (no edit path) | a commission entry records work done: only its settlement may change |
| 58 | `trg_ce_must_have_worked` (1/3) <br> *before insert on* `commission_entry` | procedure_session, treatment_procedure | that staff member did not work this session |
| 59 | `trg_ce_must_have_worked` (2/3) <br> *before insert on* `commission_entry` | procedure_session, treatment_procedure | commission is earned on completed work only |
| 60 | `trg_ce_must_have_worked` (3/3) <br> *before insert on* `commission_entry` | procedure_session, treatment_procedure | free rework earns no commission: the clinic was at fault |
| 61 | `trg_ce_not_own_treatment` <br> *before insert on* `commission_entry` | session → plan → patient → user | no commission on your own treatment: the staff member is the patient |
| 62 | `trg_ce_settles_into_own_period` (1/2) <br> *before insert on* `commission_entry` | payroll_record | that payroll record belongs to a different staff member |
| 63 | `trg_ce_settles_into_own_period` (2/2) <br> *before insert on* `commission_entry` | payroll_record | that commission was not earned inside this pay period |
| 64 | `trg_ce_settles_into_own_period_upd` (1/2) <br> *before update on* `commission_entry` | payroll_record | that payroll record belongs to a different staff member |
| 65 | `trg_ce_settles_into_own_period_upd` (2/2) <br> *before update on* `commission_entry` | payroll_record | that commission was not earned inside this pay period |
| 66 | `trg_payroll_approval_validates` (1/4) <br> *before update of status on* `payroll_record` | attendance, entries, adjustments | base_pay does not follow from the wage rate and the hours logged |
| 67 | `trg_payroll_approval_validates` (2/4) <br> *before update of status on* `payroll_record` | attendance, entries, adjustments | total_hours_worked does not match the attendance settled into this record |
| 68 | `trg_payroll_approval_validates` (3/4) <br> *before update of status on* `payroll_record` | attendance, entries, adjustments | commission_total does not equal the entries settled into this record |
| 69 | `trg_payroll_approval_validates` (4/4) <br> *before update of status on* `payroll_record` | attendance, entries, adjustments | credits and debits do not equal the adjustments settled into this record |
| 70 | `trg_payroll_locked_once_approved` <br> *before update on* `payroll_record` | —  (no edit path once approved) | an approved payroll record is immutable: raise a new adjustment instead |
| 71 | `trg_payroll_no_overlap` <br> *before insert on* `payroll_record` | other payroll_record rows | that pay period overlaps another already recorded for this staff member |
| 72 | `trg_rpl_is_a_receptionist` <br> *before insert on* `receptionist_performance_log` | app_user.role | only a receptionist earns a receptionist performance bounty |
| 73 | `trg_notif_content_immutable` <br> *before update on* `notification` | —  (no edit path) | a sent notification is a record of what was sent: only its read state may change |
| 74 | `trg_notif_not_to_departed` <br> *before insert on* `notification` | staff_profile | that staff member has left the clinic |
| 75 | `trg_notif_patient_sees_own` (1/4) <br> *before insert on* `notification` | appointment / invoice / plan / procedure | that appointment belongs to another patient |
| 76 | `trg_notif_patient_sees_own` (2/4) <br> *before insert on* `notification` | appointment / invoice / plan / procedure | that invoice belongs to another patient |
| 77 | `trg_notif_patient_sees_own` (3/4) <br> *before insert on* `notification` | appointment / invoice / plan / procedure | that treatment plan belongs to another patient |
| 78 | `trg_notif_patient_sees_own` (4/4) <br> *before insert on* `notification` | appointment / invoice / plan / procedure | that procedure belongs to another patient |
| 79 | `trg_notif_read_is_one_way` <br> *before update of is_read on* `notification` | —  (single row) | a notification cannot be un-read |
| 80 | `trg_notif_target_exists` (1/8) <br> *before insert on* `notification` | eight possible target tables | the appointment this notification refers to does not exist |
| 81 | `trg_notif_target_exists` (2/8) <br> *before insert on* `notification` | eight possible target tables | the treatment plan this notification refers to does not exist |
| 82 | `trg_notif_target_exists` (3/8) <br> *before insert on* `notification` | eight possible target tables | the procedure this notification refers to does not exist |
| 83 | `trg_notif_target_exists` (4/8) <br> *before insert on* `notification` | eight possible target tables | the invoice this notification refers to does not exist |
| 84 | `trg_notif_target_exists` (5/8) <br> *before insert on* `notification` | eight possible target tables | the treatment failure this notification refers to does not exist |
| 85 | `trg_notif_target_exists` (6/8) <br> *before insert on* `notification` | eight possible target tables | the inventory item this notification refers to does not exist |
| 86 | `trg_notif_target_exists` (7/8) <br> *before insert on* `notification` | eight possible target tables | the equipment this notification refers to does not exist |
| 87 | `trg_notif_target_exists` (8/8) <br> *before insert on* `notification` | eight possible target tables | the payroll record this notification refers to does not exist |
| 88 | *no trigger — new with Phase P* <br> *on booking a* `booking_request` | `booking_request.status` | this booking request has already been handled |
| 89 | *no trigger — new with Phase P* <br> *on booking a* `booking_request` | `appointment` | *atomicity, not a refusal — the appointment and the request's new status commit together* |

> **Rules 88–89 never had a trigger.** Every rule above was extracted from one that existed
> before the triggers were removed; these two arrive with the `booking_request` entity in
> Phase P, and are listed here because this document is the API's specification, not a record
> of what SQLite used to do.

---

## By module

| Module | | Triggers | Rules |
|---|---|---|---|
| 3 | Scheduling | 5 | 6 |
| 4 | Treatment Planning | 5 | 8 |
| 5 | Clinical Record | 5 | 6 |
| 6 | Billing | 9 | 14 |
| 7 | Inventory | 7 | 8 |
| 8 | Payroll & Commission | 20 | 30 |
| 9 | Notifications | 5 | 15 |
| 10 | Booking Requests | 0 | 2 |
| | **total** | **56** | **89** |

---

## The seven derived-value rules

These carry no refusal message; they *maintain* data. Removing them means the API
becomes responsible for writing these values on every path that touches them, and
the seed files now do so explicitly as a working example of what the API must do.

| Trigger | Maintained |
|---|---|
| `trg_decision_applies` | treatment_procedure.status |
| `trg_invoice_totals_ins` | invoice subtotal/vat/total |
| `trg_line_settles_session` | procedure_session billed state |
| `trg_line_binds_procedure_price` | unit_price and billable_amount |
| `trg_payment_settles` | invoice.status |
| `trg_line_resettles` | invoice totals after a credit |
| `trg_log_applies` | quantity_on_hand and quantity_remaining |

Two of these are candidates for becoming **views** rather than API-maintained columns,
removing the duplicated state entirely: `treatment_procedure.status` (the head of the
decision log) and the inventory quantities (a sum of the log). Invoice totals must stay
stored — a Vietnamese legal invoice records what was printed, not a later recomputation.

---

## Retrieving the original implementations

Every trigger body remains in git. The last commit before removal:

```
git show 8d9ec14:db/modules/0801_payroll_schema.sql
```
