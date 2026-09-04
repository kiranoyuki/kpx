-- =============================================================================
-- KPX — MODULE 9 seed: Notifications
--
-- The cases that matter:
--   · a SYSTEM message with no sender — the reminder nobody typed
--   · a PAGE, direct and urgent, from the floor to a named doctor
--   · an ANNOUNCEMENT broadcast to a ROLE, which no single person can mark read
--   · every kind of polymorphic link, each pointing at a row that exists
--   · a message to a PROVISIONAL patient who has no email and no login
--   · read and unread, and the no-show chase that is still waiting to be sent
-- =============================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- ------------------------------------------------- to patients, system-sent --
INSERT INTO notification (id, sender_id, recipient_id, recipient_role, type, title, body, related_entity_type, related_entity_id, is_read, read_at, sent_at) VALUES

-- A reminder for tomorrow's confirmed appointment. No sender: the schedule
-- raised it, not a person.
('nt-01', NULL, 'u-pat03', NULL, 'Reminder',
 'Appointment tomorrow at 09:00',
 'Nhắc lịch hẹn: you have an appointment tomorrow at 09:00 with Dr Tran Van Minh. Please arrive ten minutes early.',
 'Appointment','ap-05', 1, '2026-09-02 19:12:00', '2026-09-02 18:00:00'),

-- THE NO-SHOW CHASE. ap-03 was a no-show; this is the reschedule prompt the
-- design has been carrying since the beginning. The recipient is PROVISIONAL —
-- booked online, never arrived, has no login and no email — which is exactly
-- why delivery is by phone and why this record has to exist independently of it.
('nt-02', 'u-rec01', 'u-prv02', NULL, 'Reminder',
 'We missed you — shall we rebook?',
 'You did not arrive for your consultation on 20 August. Reply or call 028 3822 1177 and we will find you another time. No charge for the missed visit.',
 'Appointment','ap-03', 0, NULL, '2026-08-20 17:30:00'),

-- An outstanding balance on the one PartiallyPaid invoice.
('nt-03', 'u-acc01', 'u-pat03', NULL, 'Reminder',
 'Balance outstanding on your treatment',
 'A balance of 1,160,000 remains on your invoice for the composite filling on tooth 37. You can settle it at reception on your next visit or by transfer.',
 'Invoice','inv-05', 0, NULL, '2026-09-03 16:00:00'),

-- A treatment plan waiting on the patient's decision.
('nt-04', 'u-doc04', 'u-pat02', NULL, 'Reminder',
 'Your treatment plan is ready to review',
 'Dr Lam Thi Quynh has prepared a plan for your review. Reception can walk you through the costs before you decide.',
 'TreatmentPlan','tp-02', 0, NULL, '2026-08-26 11:00:00'),

-- ------------------------------------------------------ staff, person to person --
-- A PAGE: direct, urgent, to a named person. A page broadcast to a role is one
-- nobody answers, which is why the schema refuses it.
('nt-05', 'u-rec01', 'u-doc01', NULL, 'Page',
 'Chair 2 — patient waiting',
 'Your 10:30 has arrived early and is seated in chair 2.',
 'Appointment','ap-07', 1, '2026-09-03 10:19:00', '2026-09-03 10:18:00'),

('nt-06', 'u-ast01', 'u-doc04', NULL, 'Page',
 'Sterilisation cycle finished',
 'The autoclave load for your 14:30 is out and cooling.',
 'Equipment','eq-auto', 0, NULL, '2026-09-03 13:55:00'),

-- ------------------------------------------------------ alerts to the manager --
-- System-raised, no sender. These are the operational alarms modules 6-8 make
-- possible: stock, equipment, a failed treatment, a payslip.
('nt-07', NULL, 'u-mgr01', NULL, 'Alert',
 'Low stock: composite A2',
 'On-hand quantity has fallen to the reorder threshold. Vendor Nha Khoa Viet Phat, lead time about five days.',
 'InventoryItem','it-comp-a2', 0, NULL, '2026-09-03 07:00:00'),

('nt-08', NULL, 'u-mgr01', NULL, 'Alert',
 'Handpiece overdue for service',
 'This handpiece is past its service interval and is currently marked UnderMaintenance.',
 'Equipment','eq-hp-02', 1, '2026-09-01 08:40:00', '2026-09-01 08:00:00'),

-- The failed extraction that drove the module 8 chargeback.
('nt-09', 'u-doc02', 'u-mgr01', NULL, 'Alert',
 'Treatment failure recorded — #46 extraction',
 'A retained root fragment was found at review. Fault attributed to clinic technique; refund issued and the rework will be done at no charge.',
 'TreatmentFailure','tf-01', 1, '2026-09-01 11:30:00', '2026-09-01 09:15:00'),

('nt-10', NULL, 'u-ast01', NULL, 'Reminder',
 'Your August payslip is ready',
 'August has been approved and paid. Your rate changed mid-month; each day is priced at the rate in force on that day.',
 'PayrollRecord','pay-2608-ast01', 0, NULL, '2026-09-01 10:05:00'),

-- ------------------------------------------------------------- broadcasts --
-- To a ROLE, not a person. Nobody can mark these read: there is no single
-- reader to read them. Per-recipient read state arrives with the delivery
-- system, and until then a broadcast stays unread by construction.
('nt-11', 'u-mgr01', NULL, 'Assistant', 'Announcement',
 'Instrument tracking from Monday',
 'From Monday every instrument cassette is scanned out and back at the sterilisation bench. Nam will show the new log at the morning huddle.',
 NULL, NULL, 0, NULL, '2026-09-02 17:00:00'),

('nt-12', 'u-mgr01', NULL, 'Doctor', 'Announcement',
 'Implant contract rates reviewed',
 'Individual implant rates have been reviewed for the coming quarter. Speak to me directly if your contract terms have changed.',
 NULL, NULL, 0, NULL, '2026-09-01 12:00:00'),

('nt-13', 'u-mgr01', NULL, 'Receptionist', 'Announcement',
 'Follow-up bounty unchanged this quarter',
 'The per-event rates for new registrations and successful follow-ups are unchanged. Keep logging them as they happen.',
 NULL, NULL, 0, NULL, '2026-09-01 12:05:00'),

-- A broadcast to PATIENTS: the clinic-wide notice.
('nt-14', 'u-mgr01', NULL, 'Patient', 'Announcement',
 'Clinic closed 2 September for National Day',
 'Nghi le Quoc khanh: the clinic is closed on 2 September. Appointments that day have been moved and reception has called everyone affected.',
 NULL, NULL, 0, NULL, '2026-08-20 09:00:00');

COMMIT;
