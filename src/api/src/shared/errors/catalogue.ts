/**
 * The machine-readable source of truth for error wording.
 *
 * `conventions.md` §8: **codes are the contract; messages are presentation.**
 * Rule tests assert `code` and never wording, because wording will change —
 * `vi` is null throughout and filling it in is the whole of the Vietnamese
 * work in Phase J.
 *
 * `Design/rule-catalogue.md` stays the **design document**: its 89 rows and the
 * "needs to look at" column are the specification and the reason each rule
 * exists. It is not machine-synced and no test parses it. A test that scrapes
 * prose Markdown is worse than no test — it fails on formatting and passes on a
 * wrong message.
 *
 * ## Two kinds of entry
 *
 * - **`rule: n`** — one of the 89 numbered rules in `rule-catalogue.md`, ported
 *   into the API. These arrive as their phases land; scheduling's 1-6 come with
 *   Phase B1.
 * - **`rule: null`** — a declarative constraint the schema still enforces. These
 *   were never triggers, so they have no rule number. The 65 named `ck_*`
 *   constraints reach here through `constraint-map.ts`.
 */

export interface CatalogueEntry {
  /** Rule number in `Design/rule-catalogue.md`, or null for a schema constraint. */
  rule: number | null
  /** English display text. Never asserted by a test. */
  en: string
  /** Vietnamese. Null until Phase J fills it in. */
  vi: string | null
}

export const CATALOGUE = {
  // ---- Transport and translation (shared/errors) ----------------------------
  CONSTRAINT_VIOLATED: { rule: null, en: 'the data breaks a rule the schema enforces', vi: null },
  REFERENCED_ROW_MISSING: { rule: null, en: 'that record refers to something that does not exist', vi: null },
  DUPLICATE_VALUE: { rule: null, en: 'that value is already in use', vi: null },
  REQUIRED_FIELD_MISSING: { rule: null, en: 'a required field was left empty', vi: null },
  VALIDATION_FAILED: { rule: null, en: 'the request could not be read', vi: null },
  NOT_FOUND: { rule: null, en: 'no such route', vi: null },
  INTERNAL: { rule: null, en: 'internal server error', vi: null },

  // ---- The 65 named ck_* constraints, in schema module order ----------------
  /** `ck_user_cccd_12_digits` */
  CCCD_MUST_BE_12_DIGITS: { rule: null, en: 'national ID must be exactly 12 digits', vi: null },
  /** `ck_user_active_is_verified` */
  ACTIVE_PERSON_NEEDS_VERIFICATION: { rule: null, en: 'an Active person must record who verified them and when', vi: null },
  /** `ck_user_provisional_unverified` */
  PROVISIONAL_PERSON_CANNOT_BE_VERIFIED: { rule: null, en: 'a Provisional person cannot carry verification details', vi: null },
  /** `ck_staff_departed_has_end_date` */
  DEPARTED_STAFF_NEEDS_END_DATE: { rule: null, en: 'an end date belongs to a Departed staff member, and only to one', vi: null },
  /** `ck_staff_end_after_join` */
  STAFF_END_BEFORE_JOIN: { rule: null, en: 'employment cannot end before it began', vi: null },
  /** `ck_tooth_code_matches_parts` */
  TOOTH_CODE_MISMATCH: { rule: null, en: 'a tooth code must be its quadrant followed by its position', vi: null },
  /** `ck_tooth_dentition_quadrant` */
  TOOTH_QUADRANT_WRONG_FOR_DENTITION: { rule: null, en: 'permanent teeth sit in quadrants 1-4, primary teeth in 5-8', vi: null },
  /** `ck_tooth_primary_position` */
  PRIMARY_TOOTH_POSITION_OUT_OF_RANGE: { rule: null, en: 'a primary tooth has positions 1-5', vi: null },
  /** `ck_tooth_anterior_matches_position` */
  TOOTH_ANTERIOR_MISMATCH: { rule: null, en: 'anterior is positions 1-3; anything further back is posterior', vi: null },
  /** `ck_tooth_surfaces_match_anterior` */
  TOOTH_SURFACES_WRONG_FOR_POSITION: { rule: null, en: 'anterior teeth have surfaces MIDBL and posterior teeth MODBL', vi: null },
  /** `ck_service_scope_vs_basis` */
  SERVICE_SCOPE_BASIS_MISMATCH: { rule: null, en: 'a service with no tooth scope must be priced per procedure or per quadrant', vi: null },
  /** `ck_service_none_leaves_nothing` */
  SERVICE_NONE_LEAVES_NO_CONDITION: { rule: null, en: 'a service with no tooth scope cannot leave a resulting condition', vi: null },
  /** `ck_promo_percentage_max_100` */
  PROMOTION_PERCENTAGE_ABOVE_100: { rule: null, en: 'a percentage promotion cannot exceed 100%', vi: null },
  /** `ck_promo_window` */
  PROMOTION_WINDOW_INVERTED: { rule: null, en: 'a promotion cannot end before it starts', vi: null },
  /** `ck_sched_end_after_start` */
  SCHEDULE_END_BEFORE_START: { rule: null, en: 'a schedule block cannot end before it starts', vi: null },
  /** `ck_sched_one_mode` */
  SCHEDULE_NEEDS_ONE_MODE: { rule: null, en: 'a schedule block is either a recurring weekday or a one-off date, never both', vi: null },
  /** `ck_appt_selfbooked_is_online` */
  SELF_BOOKED_MUST_BE_ONLINE: { rule: null, en: 'an appointment with no creator must be an online self-booking', vi: null },
  /** `ck_plan_dates` */
  PLAN_END_BEFORE_START: { rule: null, en: 'a treatment plan cannot be estimated to end before it starts', vi: null },
  /** `ck_proc_completed_has_date` */
  PROCEDURE_COMPLETED_NEEDS_DATE: { rule: null, en: 'a completion date belongs to a Completed procedure, and only to one', vi: null },
  /** `ck_decision_reason_required` */
  DECISION_NEEDS_REASON: { rule: null, en: 'declining or skipping a procedure requires a reason', vi: null },
  /** `ck_discount_pct_max_100` */
  DISCOUNT_PERCENTAGE_ABOVE_100: { rule: null, en: 'a percentage discount cannot exceed 100%', vi: null },
  /** `ck_discount_reviewed` */
  DISCOUNT_REVIEW_STATE_MISMATCH: { rule: null, en: 'a Pending discount proposal has no reviewer; a reviewed one names both reviewer and time', vi: null },
  /** `ck_special_reviewed` */
  SPECIAL_REVIEW_STATE_MISMATCH: { rule: null, en: 'a Pending special-procedure proposal has no reviewer; a reviewed one names both reviewer and time', vi: null },
  /** `ck_cond_resolved_has_date` */
  CONDITION_RESOLVED_NEEDS_DATE: { rule: null, en: 'a resolved date belongs to a Resolved condition, and only to one', vi: null },
  /** `ck_cond_wholetooth_no_surfaces` */
  WHOLE_TOOTH_CONDITION_HAS_SURFACES: { rule: null, en: 'a whole-tooth condition cannot name surfaces', vi: null },
  /** `ck_session_completed_has_time` */
  SESSION_COMPLETED_NEEDS_TIME: { rule: null, en: 'a completion time belongs to a Completed session, and only to one', vi: null },
  /** `ck_failure_resolved_complete` */
  FAILURE_RESOLUTION_INCOMPLETE: { rule: null, en: 'a Resolved failure needs its fault, its remedy, and who determined them and when', vi: null },
  /** `ck_inv_one_discount_source` */
  INVOICE_TWO_DISCOUNT_SOURCES: { rule: null, en: 'an invoice takes a voucher or an approved proposal, never both', vi: null },
  /** `ck_inv_number_only_when_issued` */
  INVOICE_NUMBER_STATE_MISMATCH: { rule: null, en: 'a Draft invoice has no number; an issued one needs number, serial and issue time', vi: null },
  /** `ck_inv_total` */
  INVOICE_TOTAL_MISMATCH: { rule: null, en: 'invoice total must equal subtotal minus discount plus VAT', vi: null },
  /** `ck_line_one_source` */
  LINE_NEEDS_ONE_SOURCE: { rule: null, en: 'an invoice line bills either a session or a procedure, never both', vi: null },
  /** `ck_line_vat_after_discount` */
  LINE_VAT_MISCOMPUTED: { rule: null, en: 'VAT is computed on the line total after its discount, never before', vi: null },
  /** `ck_line_discount_within` */
  LINE_DISCOUNT_EXCEEDS_TOTAL: { rule: null, en: 'a line discount cannot exceed the line total', vi: null },
  /** `ck_line_total_is_price_times_qty` */
  LINE_TOTAL_MISMATCH: { rule: null, en: 'line total must be unit price times quantity, negated on a credit line', vi: null },
  /** `ck_equip_retired_has_date` */
  EQUIPMENT_RETIRED_NEEDS_DATE: { rule: null, en: 'a retirement date belongs to Retired equipment, and only to it', vi: null },
  /** `ck_batch_remaining_within` */
  BATCH_REMAINING_EXCEEDS_RECEIVED: { rule: null, en: 'a batch cannot hold more than it received', vi: null },
  /** `ck_batch_not_born_expired` */
  BATCH_ALREADY_EXPIRED: { rule: null, en: 'a batch cannot expire on or before the day it arrived', vi: null },
  /** `ck_log_sign_matches_type` */
  LOG_SIGN_WRONG_FOR_TYPE: { rule: null, en: 'a restock adds stock; consumption, expiry and write-off remove it', vi: null },
  /** `ck_supply_one_owner` */
  SUPPLY_NEEDS_ONE_OWNER: { rule: null, en: 'a supply line belongs to a procedure or an instruction set, never both', vi: null },
  /** `ck_pay_period` */
  PAY_PERIOD_INVERTED: { rule: null, en: 'a pay period cannot end before it starts', vi: null },
  /** `ck_pay_approved` */
  PAYROLL_APPROVAL_STATE_MISMATCH: { rule: null, en: 'a Draft payroll record has no approver; any other status needs one', vi: null },
  /** `ck_pay_paid` */
  PAYROLL_PAID_STATE_MISMATCH: { rule: null, en: 'a paid date belongs to a Paid payroll record, and only to one', vi: null },
  /** `ck_pay_net` */
  PAYROLL_NET_MISMATCH: { rule: null, en: 'net pay must equal base plus commission plus credits minus debits', vi: null },
  /** `ck_att_closed_together` */
  ATTENDANCE_CLOSE_INCOMPLETE: { rule: null, en: 'clock-out and total minutes are recorded together or not at all', vi: null },
  /** `ck_att_out_after_in` */
  ATTENDANCE_OUT_BEFORE_IN: { rule: null, en: 'a shift cannot clock out before it clocked in', vi: null },
  /** `ck_att_date_is_clock_in` */
  ATTENDANCE_DATE_MISMATCH: { rule: null, en: 'a shift is dated by the day it clocked in', vi: null },
  /** `ck_rule_pct_max_100` */
  COMMISSION_PERCENTAGE_ABOVE_100: { rule: null, en: 'a percentage commission cannot exceed 100%', vi: null },
  /** `ck_rule_one_scope` */
  COMMISSION_RULE_TWO_SCOPES: { rule: null, en: 'a commission rule scopes to a service category or an event type, never both', vi: null },
  /** `ck_rule_recep_event` */
  RECEPTIONIST_RULE_HAS_SERVICE: { rule: null, en: 'a receptionist commission rule cannot scope to a service category', vi: null },
  /** `ck_rule_clinical` */
  CLINICAL_RULE_HAS_EVENT: { rule: null, en: 'only a receptionist commission rule may scope to an event type', vi: null },
  /** `ck_rpl_followup_has_appt` */
  FOLLOWUP_NEEDS_APPOINTMENT: { rule: null, en: 'a successful follow-up must name the appointment it produced', vi: null },
  /** `ck_ce_source` */
  COMMISSION_ENTRY_SOURCE_MISMATCH: { rule: null, en: 'a commission entry cites a completed session or a receptionist event, never both', vi: null },
  /** `ck_ce_settled` */
  COMMISSION_ENTRY_SETTLEMENT_MISMATCH: { rule: null, en: 'a Pending commission entry has no payroll record; a settled one needs one', vi: null },
  /** `ck_adj_reason` */
  ADJUSTMENT_NEEDS_REASON: { rule: null, en: 'a payroll adjustment requires a reason', vi: null },
  /** `ck_adj_settled` */
  ADJUSTMENT_SETTLEMENT_MISMATCH: { rule: null, en: 'a Pending adjustment has no payroll record; a settled one needs one', vi: null },
  /** `ck_notif_title` */
  NOTIFICATION_NEEDS_TITLE: { rule: null, en: 'a notification requires a title', vi: null },
  /** `ck_notif_body` */
  NOTIFICATION_NEEDS_BODY: { rule: null, en: 'a notification requires a body', vi: null },
  /** `ck_notif_recipient` */
  NOTIFICATION_NEEDS_ONE_RECIPIENT: { rule: null, en: 'a notification goes to one person or one role, never both and never neither', vi: null },
  /** `ck_notif_target` */
  NOTIFICATION_TARGET_INCOMPLETE: { rule: null, en: 'a related entity needs both its type and its id', vi: null },
  /** `ck_notif_read` */
  NOTIFICATION_READ_STATE_MISMATCH: { rule: null, en: 'a read notification needs a read time, and an unread one must not have it', vi: null },
  /** `ck_notif_broadcast_unread` */
  BROADCAST_CANNOT_BE_READ: { rule: null, en: 'a broadcast has no single reader, so it cannot be marked read', vi: null },
  /** `ck_notif_page_is_direct` */
  PAGE_NEEDS_RECIPIENT: { rule: null, en: 'a Page goes to a named person', vi: null },
  /** `ck_notif_announce_is_broad` */
  ANNOUNCEMENT_NEEDS_ROLE: { rule: null, en: 'an Announcement goes to a role', vi: null },
  /** `ck_notif_not_self` */
  NOTIFICATION_TO_SELF: { rule: null, en: 'a notification cannot be sent to its own sender', vi: null },
  /** `ck_notif_read_after_sent` */
  NOTIFICATION_READ_BEFORE_SENT: { rule: null, en: 'a notification cannot be read before it was sent', vi: null },
} as const satisfies Record<string, CatalogueEntry>

export type ErrorCode = keyof typeof CATALOGUE

/** The English wording for a code, or undefined if the code is not catalogued. */
export function messageFor(code: string): string | undefined {
  return (CATALOGUE as Record<string, CatalogueEntry | undefined>)[code]?.en
}

/** Whether a code has an entry. Used by each module's coverage test (§8). */
export function isCatalogued(code: string): boolean {
  return messageFor(code) !== undefined
}
