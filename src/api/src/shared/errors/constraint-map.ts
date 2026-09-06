/**
 * The 65 named `ck_*` constraints → catalogue codes.
 *
 * Only **named** constraints appear here. The schema's other 111 CHECKs are
 * inline and report their own SQL predicate rather than a name (see
 * `translate.ts`), which is not a stable identifier and must never reach a
 * client. Those stay generic `CONSTRAINT_VIOLATED`.
 *
 * Adding a named constraint to the schema means adding a row here and an entry
 * in `catalogue.ts`. `constraint-map.test.ts` fails if the two drift apart, and
 * if any name here is missing from the schema.
 */

import type { ErrorCode } from './catalogue.js'

export const CONSTRAINT_TO_CODE: Readonly<Record<string, ErrorCode>> = {
  ck_user_cccd_12_digits: 'CCCD_MUST_BE_12_DIGITS',
  ck_user_active_is_verified: 'ACTIVE_PERSON_NEEDS_VERIFICATION',
  ck_user_provisional_unverified: 'PROVISIONAL_PERSON_CANNOT_BE_VERIFIED',
  ck_staff_departed_has_end_date: 'DEPARTED_STAFF_NEEDS_END_DATE',
  ck_staff_end_after_join: 'STAFF_END_BEFORE_JOIN',
  ck_tooth_code_matches_parts: 'TOOTH_CODE_MISMATCH',
  ck_tooth_dentition_quadrant: 'TOOTH_QUADRANT_WRONG_FOR_DENTITION',
  ck_tooth_primary_position: 'PRIMARY_TOOTH_POSITION_OUT_OF_RANGE',
  ck_tooth_anterior_matches_position: 'TOOTH_ANTERIOR_MISMATCH',
  ck_tooth_surfaces_match_anterior: 'TOOTH_SURFACES_WRONG_FOR_POSITION',
  ck_service_scope_vs_basis: 'SERVICE_SCOPE_BASIS_MISMATCH',
  ck_service_none_leaves_nothing: 'SERVICE_NONE_LEAVES_NO_CONDITION',
  ck_promo_percentage_max_100: 'PROMOTION_PERCENTAGE_ABOVE_100',
  ck_promo_window: 'PROMOTION_WINDOW_INVERTED',
  ck_sched_end_after_start: 'SCHEDULE_END_BEFORE_START',
  ck_sched_one_mode: 'SCHEDULE_NEEDS_ONE_MODE',
  ck_appt_selfbooked_is_online: 'SELF_BOOKED_MUST_BE_ONLINE',
  ck_plan_dates: 'PLAN_END_BEFORE_START',
  ck_proc_completed_has_date: 'PROCEDURE_COMPLETED_NEEDS_DATE',
  ck_decision_reason_required: 'DECISION_NEEDS_REASON',
  ck_discount_pct_max_100: 'DISCOUNT_PERCENTAGE_ABOVE_100',
  ck_discount_reviewed: 'DISCOUNT_REVIEW_STATE_MISMATCH',
  ck_special_reviewed: 'SPECIAL_REVIEW_STATE_MISMATCH',
  ck_cond_resolved_has_date: 'CONDITION_RESOLVED_NEEDS_DATE',
  ck_cond_wholetooth_no_surfaces: 'WHOLE_TOOTH_CONDITION_HAS_SURFACES',
  ck_session_completed_has_time: 'SESSION_COMPLETED_NEEDS_TIME',
  ck_failure_resolved_complete: 'FAILURE_RESOLUTION_INCOMPLETE',
  ck_inv_one_discount_source: 'INVOICE_TWO_DISCOUNT_SOURCES',
  ck_inv_number_only_when_issued: 'INVOICE_NUMBER_STATE_MISMATCH',
  ck_inv_total: 'INVOICE_TOTAL_MISMATCH',
  ck_line_one_source: 'LINE_NEEDS_ONE_SOURCE',
  ck_line_vat_after_discount: 'LINE_VAT_MISCOMPUTED',
  ck_line_discount_within: 'LINE_DISCOUNT_EXCEEDS_TOTAL',
  ck_line_total_is_price_times_qty: 'LINE_TOTAL_MISMATCH',
  ck_equip_retired_has_date: 'EQUIPMENT_RETIRED_NEEDS_DATE',
  ck_batch_remaining_within: 'BATCH_REMAINING_EXCEEDS_RECEIVED',
  ck_batch_not_born_expired: 'BATCH_ALREADY_EXPIRED',
  ck_log_sign_matches_type: 'LOG_SIGN_WRONG_FOR_TYPE',
  ck_supply_one_owner: 'SUPPLY_NEEDS_ONE_OWNER',
  ck_pay_period: 'PAY_PERIOD_INVERTED',
  ck_pay_approved: 'PAYROLL_APPROVAL_STATE_MISMATCH',
  ck_pay_paid: 'PAYROLL_PAID_STATE_MISMATCH',
  ck_pay_net: 'PAYROLL_NET_MISMATCH',
  ck_att_closed_together: 'ATTENDANCE_CLOSE_INCOMPLETE',
  ck_att_out_after_in: 'ATTENDANCE_OUT_BEFORE_IN',
  ck_att_date_is_clock_in: 'ATTENDANCE_DATE_MISMATCH',
  ck_rule_pct_max_100: 'COMMISSION_PERCENTAGE_ABOVE_100',
  ck_rule_one_scope: 'COMMISSION_RULE_TWO_SCOPES',
  ck_rule_recep_event: 'RECEPTIONIST_RULE_HAS_SERVICE',
  ck_rule_clinical: 'CLINICAL_RULE_HAS_EVENT',
  ck_rpl_followup_has_appt: 'FOLLOWUP_NEEDS_APPOINTMENT',
  ck_ce_source: 'COMMISSION_ENTRY_SOURCE_MISMATCH',
  ck_ce_settled: 'COMMISSION_ENTRY_SETTLEMENT_MISMATCH',
  ck_adj_reason: 'ADJUSTMENT_NEEDS_REASON',
  ck_adj_settled: 'ADJUSTMENT_SETTLEMENT_MISMATCH',
  ck_notif_title: 'NOTIFICATION_NEEDS_TITLE',
  ck_notif_body: 'NOTIFICATION_NEEDS_BODY',
  ck_notif_recipient: 'NOTIFICATION_NEEDS_ONE_RECIPIENT',
  ck_notif_target: 'NOTIFICATION_TARGET_INCOMPLETE',
  ck_notif_read: 'NOTIFICATION_READ_STATE_MISMATCH',
  ck_notif_broadcast_unread: 'BROADCAST_CANNOT_BE_READ',
  ck_notif_page_is_direct: 'PAGE_NEEDS_RECIPIENT',
  ck_notif_announce_is_broad: 'ANNOUNCEMENT_NEEDS_ROLE',
  ck_notif_not_self: 'NOTIFICATION_TO_SELF',
  ck_notif_read_after_sent: 'NOTIFICATION_READ_BEFORE_SENT',
}
