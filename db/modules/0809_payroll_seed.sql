-- =============================================================================
-- KPX — MODULE 8 seed: Payroll & Commission
--
-- August 2026 is run and approved; September is still accruing.
--
-- The cases that matter:
--   · a MID-PERIOD RAISE — the assistant's rate rises on 16 August, and each
--     day is priced at the rate in force THAT DAY. 3 days at 45,000 and
--     5 at 55,000, with no special handling anywhere
--   · a CONTRACT RATE beating a role rate beating the catch-all
--   · commission credited to whoever WORKED each session, not to the plan's
--     owning doctor
--   · a PENDING DEBIT charged back for the failed extraction (tf-01)
--   · free rework earning nothing, by arithmetic
-- =============================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- ------------------------------------------------------------- wage rates --
INSERT INTO wage_rate (id, staff_id, wage_type, rate, effective_from, reason, set_by) VALUES
('wr-01','st-mgr01','Monthly',25000000,'2024-06-01','Founding salary.','u-mgr01'),
('wr-02','st-doc01','Monthly',40000000,'2024-06-01','Founding salary.','u-mgr01'),
('wr-03','st-doc02','Monthly',35000000,'2024-09-15','On joining.','u-mgr01'),
('wr-04','st-doc04','Monthly',32000000,'2025-03-01','On joining.','u-mgr01'),
('wr-05','st-rec01','Monthly',12000000,'2024-06-10','On joining.','u-mgr01'),
('wr-06','st-acc01','Monthly',15000000,'2024-06-20','On joining.','u-mgr01'),
('wr-07','st-doc03','Monthly',34000000,'2024-08-01','On joining.','u-mgr01'),
-- THE MID-PERIOD RAISE. The intern rate is not overwritten: it stays, so the
-- days before 16 August are still priced at 45,000 forever.
('wr-08','st-ast01','Hourly',    45000,'2026-07-01','Trainee rate on starting.','u-mgr01'),
('wr-09','st-ast01','Hourly',    55000,'2026-08-16','Rate review after six weeks.','u-mgr01');

-- ------------------------------------------------------- commission rules --
INSERT INTO commission_rule (id, role, staff_id, service_category_id, event_type, commission_type, commission_value, effective_from, set_by, notes) VALUES
('cr-01','Doctor',      NULL,      NULL,   NULL,'Percentage',   15,'2025-01-01','u-mgr01','Catch-all doctor rate.'),
('cr-02','Assistant',   NULL,      NULL,   NULL,'Percentage',    5,'2025-01-01','u-mgr01','Catch-all assistant rate.'),
('cr-03','Doctor',      NULL,      'sc-07',NULL,'Percentage',   20,'2025-01-01','u-mgr01','Implant uplift, role level.'),
-- an INDIVIDUAL CONTRACT rate: beats cr-03, which beats cr-01
('cr-04','Doctor',      'st-doc01','sc-07',NULL,'Percentage',   22,'2025-01-01','u-mgr01','Dr Minh implant contract rate.'),
('cr-05','Receptionist',NULL,      NULL,'NewPatientRegistered','FixedAmount',100000,'2025-01-01','u-mgr01','Per new patient completing a first visit.'),
('cr-06','Receptionist',NULL,      NULL,'SuccessfulFollowUp',  'FixedAmount', 50000,'2025-01-01','u-mgr01','Per completed follow-up booking.');

-- --------------------------------------------------------------- attendance --
-- Only the hourly assistant clocks in; monthly staff do not.
INSERT INTO attendance_log (id, staff_id, date, clock_in, clock_out, total_minutes, notes) VALUES
('at-01','st-ast01','2026-08-03','2026-08-03 08:00:00','2026-08-03 16:00:00',480,NULL),
('at-02','st-ast01','2026-08-04','2026-08-04 08:00:00','2026-08-04 16:00:00',480,NULL),
('at-03','st-ast01','2026-08-05','2026-08-05 08:00:00','2026-08-05 16:00:00',480,NULL),
('at-04','st-ast01','2026-08-18','2026-08-18 08:00:00','2026-08-18 16:00:00',480,NULL),
('at-05','st-ast01','2026-08-19','2026-08-19 08:00:00','2026-08-19 16:00:00',480,NULL),
('at-06','st-ast01','2026-08-20','2026-08-20 08:00:00','2026-08-20 16:00:00',480,NULL),
('at-07','st-ast01','2026-08-25','2026-08-25 08:00:00','2026-08-25 16:00:00',480,NULL),
('at-08','st-ast01','2026-08-26','2026-08-26 08:00:00','2026-08-26 15:30:00',450,'Left early, dental appointment.'),
-- September, still accruing and not yet in any payroll
('at-09','st-ast01','2026-09-01','2026-09-01 08:00:00','2026-09-01 17:00:00',540,NULL),
('at-10','st-ast01','2026-09-02','2026-09-02 08:00:00','2026-09-02 16:00:00',480,NULL),
('at-11','st-ast01','2026-09-03','2026-09-03 08:00:00',NULL,NULL,'Shift still open.');

-- ------------------------------------------- receptionist performance events --
INSERT INTO receptionist_performance_log (id, receptionist_id, event_type, patient_id, appointment_id, occurred_at) VALUES
('rpl-01','st-rec01','NewPatientRegistered','pp-01','ap-01','2026-08-25 09:45:00'),
('rpl-02','st-rec01','NewPatientRegistered','pp-02','ap-02','2026-08-25 10:00:00'),
('rpl-03','st-rec01','SuccessfulFollowUp',  'pp-04','ap-06','2026-09-02 14:30:00');

-- ----------------------------------------------------------- the payroll run --
-- August 2026, approved and paid. base_pay for monthly staff is the salary in
-- force; for the assistant it is hours x the rate on each day.
INSERT INTO payroll_record (id, staff_id, period_start, period_end, total_hours_worked, base_pay, commission_total, total_credits, total_debits, net_pay, status, approved_by, approved_at, paid_at, notes) VALUES
('pay-2608-mgr01','st-mgr01','2026-08-01','2026-08-31', 0,25000000,      0,0,0,25000000,'Paid','u-mgr01','2026-09-01 09:00:00','2026-09-01 10:00:00',NULL),
('pay-2608-doc01','st-doc01','2026-08-01','2026-08-31', 0,40000000, 210000,0,0,40210000,'Paid','u-mgr01','2026-09-01 09:00:00','2026-09-01 10:00:00',NULL),
('pay-2608-doc02','st-doc02','2026-08-01','2026-08-31', 0,35000000,      0,0,0,35000000,'Paid','u-mgr01','2026-09-01 09:00:00','2026-09-01 10:00:00','On maternity leave.'),
('pay-2608-doc04','st-doc04','2026-08-01','2026-08-31', 0,32000000,  30000,0,0,32030000,'Paid','u-mgr01','2026-09-01 09:00:00','2026-09-01 10:00:00',NULL),
('pay-2608-rec01','st-rec01','2026-08-01','2026-08-31', 0,12000000, 200000,0,0,12200000,'Paid','u-mgr01','2026-09-01 09:00:00','2026-09-01 10:00:00',NULL),
('pay-2608-acc01','st-acc01','2026-08-01','2026-08-31', 0,15000000,      0,0,0,15000000,'Paid','u-mgr01','2026-09-01 09:00:00','2026-09-01 10:00:00',NULL),
-- 63.5 hours: 24 at the trainee rate, 39.5 after the raise
('pay-2608-ast01','st-ast01','2026-08-01','2026-08-31',63.5,3252500, 60000,0,0, 3312500,'Paid','u-mgr01','2026-09-01 09:00:00','2026-09-01 10:00:00','Rate rose on 16 August; each day priced at the rate then in force.');

UPDATE attendance_log SET payroll_record_id='pay-2608-ast01' WHERE date BETWEEN '2026-08-01' AND '2026-08-31';

-- ------------------------------------------------------- commission entries --
-- AUGUST — settled into the payroll above.
INSERT INTO commission_entry (id, staff_id, source_type, session_id, performance_log_id, commission_rule_id, commission_base, amount, status, payroll_record_id, earned_at) VALUES
('ce-01','st-doc01','SessionCompleted','ps-01',NULL,'cr-01', 200000, 30000,'IncludedInPayroll','pay-2608-doc01','2026-08-25 09:45:00'),
('ce-02','st-doc01','SessionCompleted','ps-02',NULL,'cr-01',1200000,180000,'IncludedInPayroll','pay-2608-doc01','2026-08-28 14:50:00'),
('ce-03','st-ast01','SessionCompleted','ps-02',NULL,'cr-02',1200000, 60000,'IncludedInPayroll','pay-2608-ast01','2026-08-28 14:50:00'),
('ce-04','st-doc04','SessionCompleted','ps-04',NULL,'cr-01', 200000, 30000,'IncludedInPayroll','pay-2608-doc04','2026-08-25 10:00:00'),
('ce-05','st-rec01','ReceptionistEvent',NULL,'rpl-01','cr-05',0,100000,'IncludedInPayroll','pay-2608-rec01','2026-08-25 09:45:00'),
('ce-06','st-rec01','ReceptionistEvent',NULL,'rpl-02','cr-05',0,100000,'IncludedInPayroll','pay-2608-rec01','2026-08-25 10:00:00');

-- SEPTEMBER — still Pending. Note ce-07 and ce-08: Dr Quỳnh and the assistant
-- earn on Dr Minh's own whitening, because THEY did the work. Dr Minh earns
-- nothing on it — he is the patient.
INSERT INTO commission_entry (id, staff_id, source_type, session_id, performance_log_id, commission_rule_id, commission_base, amount, status, earned_at) VALUES
('ce-07','st-doc04','SessionCompleted','ps-07',NULL,'cr-01',3000000,450000,'Pending','2026-09-01 16:00:00'),
('ce-08','st-ast01','SessionCompleted','ps-07',NULL,'cr-02',3000000,150000,'Pending','2026-09-01 16:00:00'),
('ce-09','st-doc04','SessionCompleted','ps-08',NULL,'cr-01', 500000, 75000,'Pending','2026-09-01 16:25:00'),
('ce-10','st-ast01','SessionCompleted','ps-08',NULL,'cr-02', 500000, 25000,'Pending','2026-09-01 16:25:00'),
('ce-11','st-doc04','SessionCompleted','ps-06',NULL,'cr-01', 500000, 75000,'Pending','2026-09-02 14:30:00'),
('ce-12','st-ast01','SessionCompleted','ps-06',NULL,'cr-02', 500000, 25000,'Pending','2026-09-02 14:30:00'),
('ce-13','st-doc01','SessionCompleted','ps-09',NULL,'cr-01',2400000,360000,'Pending','2026-09-03 10:35:00'),
('ce-14','st-ast01','SessionCompleted','ps-09',NULL,'cr-02',2400000,120000,'Pending','2026-09-03 10:35:00'),
('ce-15','st-rec01','ReceptionistEvent',NULL,'rpl-03','cr-06',0,50000,'Pending','2026-09-02 14:30:00');

-- ---------------------------------------------------------- the chargeback --
-- tf-01: a retained root fragment, judged the clinic's own technique. The
-- clinic refunded 1,200,000 and is redoing the work free. The loss charged back
-- to the operating dentist exceeds the refund, because the lab time and the
-- free chair time are real losses too.
INSERT INTO payroll_adjustment (id, staff_id, direction, amount, reason, related_commission_entry_id, related_invoice_id, related_failure_id, status, created_by, created_at) VALUES
('adj-01','st-doc01','Debit',1500000,
 'Retained root fragment at extraction of #46 (tf-01). Clinic refunded the 1,200,000 fee and is redoing the work at no charge. Charged back at 1,500,000 to cover the refund plus the surgical chair time.',
 'ce-02','inv-01','tf-01','Pending','u-mgr01','2026-09-01 11:35:00'),
-- a credit, so both directions are exercised
('adj-02','st-ast01','Credit',500000,
 'Covered two Saturday emergency sessions at short notice in August.',
 NULL,NULL,NULL,'Pending','u-mgr01','2026-09-01 11:40:00');

COMMIT;
