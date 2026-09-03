-- =============================================================================
-- KPX — MODULE 4 seed: Treatment Planning
--
-- 5 plans, 11 procedures, 3 instruction templates, 2 proposals.
--
-- Every procedure starts Proposed and is walked to its final state by
-- procedure_decision rows — the log is authoritative and a trigger keeps
-- treatment_procedure.status in step. Nothing sets status directly.
--
-- Deliberate edge cases:
--   · a DECLINED procedure with a reason and an explained risk — informed refusal
--   · a procedure declined, then RE-PROPOSED months later and accepted, with
--     both decisions surviving in the log
--   · a special procedure held at Pending, blocking its plan
--   · a staff member (Dr Minh) being treated as a patient by a colleague
--   · unit_price NULL everywhere: nothing has been invoiced yet
-- =============================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- --------------------------------------------------------- instruction sets --
INSERT INTO procedure_instruction (id, created_by, service_category_id, title, instructions, supplies_required, version, updated_at) VALUES
('pi-01','st-doc01','sc-07','Single implant, staged','1. CBCT and surgical guide. 2. Flap, osteotomy to depth. 3. Place fixture, target 35 Ncm. 4. Cover screw, suture. 5. Heal 4 months before loading.','Implant motor, surgical kit, fixture, cover screw, 4-0 suture',2,'2026-05-02 09:00:00'),
('pi-02','st-doc01','sc-05','Root canal, single visit','1. Rubber dam. 2. Access, locate canals. 3. Working length. 4. Shape and irrigate. 5. Obturate, temporary restoration.','Rubber dam, files, NaOCl, gutta-percha, sealer',1,'2025-11-01 09:00:00'),
('pi-03','st-doc04','sc-02','Scale and polish','1. Ultrasonic supragingival. 2. Hand scale subgingival. 3. Polish with prophy paste. 4. Oral hygiene instruction.','Ultrasonic tip, curettes, prophy cup and paste',1,'2025-04-01 09:00:00');

-- ---------------------------------------------------------------- the plans --
INSERT INTO treatment_plan (id, patient_id, doctor_id, title, status, is_special, payment_mode, start_date, estimated_end_date, notes, created_at, updated_at) VALUES
('tp-01','pp-01','st-doc01','Lower right molar implant — #46','Active',        1,'PerSession','2026-08-25','2027-03-31','Bone density adequate on CBCT. Staged: extract, heal, place fixture, crown.','2026-08-25 09:40:00','2026-08-25 10:20:00'),
('tp-02','pp-02','st-doc04','Full fixed orthodontic course',   'PendingApproval',1,'Upfront',  NULL,        NULL,        'Class II div 1. Awaiting manager approval on the appliance course.',        '2026-08-25 10:00:00','2026-08-25 10:00:00'),
('tp-03','pp-03','st-doc01','Root canal and crown — #36',      'Active',        0,'PerSession','2026-09-03',  '2026-11-30','Irreversible pulpitis. RCT then crown.',                                    '2026-08-28 09:30:00','2026-08-30 14:00:00'),
('tp-04','pp-04','st-doc04','Six-month hygiene recall',        'Completed',     0,'PerSession','2026-09-02',  '2026-09-02','Routine recall, no active disease.',                                        '2026-08-30 11:00:00','2026-09-02 14:40:00'),
('tp-05','pp-05','st-doc04','Whitening and hygiene — staff',   'Completed',     0,'PerSession','2026-09-01','2026-09-01','Dr Minh as a patient, treated by Dr Quỳnh. Earns him no commission.',        '2026-08-31 17:00:00','2026-09-01 16:30:00');

-- ----------------------------------------------------------- the procedures --
-- All start Proposed; decisions below move them.
INSERT INTO treatment_procedure (id, treatment_plan_id, service_category_id, material_option_id, instruction_set_id, sequence, planned_sessions, doctor_note) VALUES
('pr-01','tp-01','sc-01',NULL,          NULL, 1,1,'CBCT ordered. Staged implant plan discussed and costed.'),
('pr-02','tp-01','sc-04',NULL,          NULL, 2,1,'Atraumatic extraction #46, socket preserved.'),
('pr-03','tp-01','sc-07','mo-impl-oss','pi-01',3,2,'Fixture placement, then abutment at 4 months.'),
('pr-04','tp-01','sc-06','mo-crown-zir',NULL, 4,2,'Crown once osseointegration is confirmed.'),
('pr-05','tp-02','sc-01',NULL,          NULL, 1,1,'Records taken, Class II div 1 confirmed.'),
('pr-06','tp-02','sc-08','mo-orth-cer', NULL, 2,1,'Ceramic brackets, 20-month course.'),
('pr-07','tp-03','sc-05',NULL,         'pi-02',1,1,'RCT #36, single visit.'),
('pr-08','tp-03','sc-06','mo-crown-pfm',NULL, 2,2,'Crown prep then fit.'),
('pr-09','tp-03','sc-03','mo-fill-std', NULL, 3,1,'Small occlusal lesion on #37, opportunistic.'),
('pr-10','tp-04','sc-02',NULL,         'pi-03',1,1,'Scale and polish, OHI given.'),
('pr-11','tp-05','sc-09',NULL,          NULL, 1,1,'In-clinic whitening session. VAT-bearing: cosmetic, not medical.'),
('pr-12','tp-05','sc-02',NULL,         'pi-03',2,1,'Scale and polish at the same visit. Zero-rated: medical.');

-- ------------------------------------------------------------- the decisions --
-- Each procedure is walked from creation to its present state. from_status must
-- match where the procedure actually is, so these are ordered chains.
INSERT INTO procedure_decision (id, procedure_id, from_status, to_status, decided_by, decided_at, reason, risk_explained, note) VALUES
-- pr-01 consultation, delivered
('d-01','pr-01',NULL,        'Proposed',  'u-doc01','2026-08-25 09:40:00',NULL,NULL,'Plan presented.'),
('d-02','pr-01','Proposed',  'Accepted',  'u-rec01','2026-08-25 09:55:00',NULL,NULL,'Patient accepted at the desk.'),
('d-03','pr-01','Accepted',  'Scheduled', 'u-rec01','2026-08-25 09:56:00',NULL,NULL,NULL),
('d-04','pr-01','Scheduled', 'InProgress','u-doc01','2026-08-25 09:00:00',NULL,NULL,NULL),
('d-05','pr-01','InProgress','Completed', 'u-doc01','2026-08-25 09:45:00',NULL,NULL,'CBCT reviewed with patient.'),
-- pr-02 extraction, delivered
('d-06','pr-02',NULL,        'Proposed',  'u-doc01','2026-08-25 09:40:00',NULL,NULL,NULL),
('d-07','pr-02','Proposed',  'Accepted',  'u-rec01','2026-08-25 09:55:00',NULL,NULL,NULL),
('d-08','pr-02','Accepted',  'Scheduled', 'u-rec01','2026-08-25 10:00:00',NULL,NULL,NULL),
('d-09','pr-02','Scheduled', 'InProgress','u-doc01','2026-08-28 14:00:00',NULL,NULL,NULL),
('d-10','pr-02','InProgress','Completed', 'u-doc01','2026-08-28 14:50:00',NULL,NULL,'Socket preserved, healing well.'),
-- pr-03 implant, accepted and scheduled but not yet started
('d-11','pr-03',NULL,        'Proposed',  'u-doc01','2026-08-25 09:40:00',NULL,NULL,'Osstem fixture quoted.'),
('d-12','pr-03','Proposed',  'Accepted',  'u-rec01','2026-08-25 09:55:00',NULL,NULL,'Accepted after manager approved the special procedure.'),
('d-13','pr-03','Accepted',  'Scheduled', 'u-rec01','2026-08-28 09:20:00',NULL,NULL,NULL),
-- pr-04 crown, still only proposed
('d-14','pr-04',NULL,        'Proposed',  'u-doc01','2026-08-25 09:40:00',NULL,NULL,'Zirconia quoted; decision deferred until the fixture integrates.'),
-- pr-05 ortho consultation, delivered
('d-15','pr-05',NULL,        'Proposed',  'u-doc04','2026-08-25 10:00:00',NULL,NULL,NULL),
('d-16','pr-05','Proposed',  'Accepted',  'u-rec01','2026-08-25 10:05:00',NULL,NULL,NULL),
('d-17','pr-05','Accepted',  'Scheduled', 'u-rec01','2026-08-25 10:06:00',NULL,NULL,NULL),
('d-18','pr-05','Scheduled', 'InProgress','u-doc04','2026-08-25 09:00:00',NULL,NULL,NULL),
('d-19','pr-05','InProgress','Completed', 'u-doc04','2026-08-25 10:00:00',NULL,NULL,'Records and photographs taken.'),
-- pr-06 braces: proposed only, blocked behind manager approval
('d-20','pr-06',NULL,        'Proposed',  'u-doc04','2026-08-25 10:00:00',NULL,NULL,'Awaiting manager approval — special procedure.'),
-- pr-07 root canal, accepted and scheduled
('d-21','pr-07',NULL,        'Proposed',  'u-doc01','2026-08-28 09:30:00',NULL,NULL,NULL),
('d-22','pr-07','Proposed',  'Accepted',  'u-rec01','2026-08-28 09:35:00',NULL,NULL,NULL),
('d-23','pr-07','Accepted',  'Scheduled', 'u-rec01','2026-08-28 09:20:00',NULL,NULL,NULL),
-- pr-08 crown, accepted
('d-24','pr-08',NULL,        'Proposed',  'u-doc01','2026-08-28 09:30:00',NULL,NULL,NULL),
('d-25','pr-08','Proposed',  'Accepted',  'u-rec01','2026-08-28 09:35:00',NULL,NULL,NULL),
-- pr-09 THE INFORMED-REFUSAL AND RE-PROPOSAL CASE:
-- declined on cost, re-proposed two months later, then accepted.
('d-26','pr-09',NULL,        'Proposed',  'u-doc01','2026-08-28 09:30:00',NULL,NULL,'Small occlusal lesion, recommended now.'),
('d-27','pr-09','Proposed',  'Declined',  'u-rec01','2026-08-28 09:40:00','Patient declined on cost; wants to wait.',1,'Explained that an untreated lesion progresses and may reach the pulp.'),
('d-28','pr-09','Declined',  'Proposed',  'u-doc01','2026-08-30 14:00:00',NULL,NULL,'Re-offered at review; lesion visibly larger.'),
('d-29','pr-09','Proposed',  'Accepted',  'u-rec01','2026-08-30 14:10:00',NULL,NULL,'Patient accepted on the second offer.'),
-- pr-10 hygiene, delivered
('d-30','pr-10',NULL,        'Proposed',  'u-doc04','2026-08-30 11:00:00',NULL,NULL,NULL),
('d-31','pr-10','Proposed',  'Accepted',  'u-rec01','2026-08-30 11:05:00',NULL,NULL,NULL),
('d-32','pr-10','Accepted',  'Scheduled', 'u-rec01','2026-08-30 11:06:00',NULL,NULL,NULL),
('d-33','pr-10','Scheduled', 'InProgress','u-doc04','2026-09-02 14:00:00',NULL,NULL,NULL),
('d-34','pr-10','InProgress','Completed', 'u-doc04','2026-09-02 14:30:00',NULL,NULL,'Generalised mild calculus removed.'),
-- pr-11 whitening for the staff patient, proposed only
('d-35','pr-11',NULL,        'Proposed',  'u-doc04','2026-08-31 17:00:00',NULL,NULL,'Colleague treating a colleague.'),
('d-36','pr-11','Proposed',  'Accepted',  'u-rec01','2026-08-31 17:10:00',NULL,NULL,NULL),
('d-37','pr-11','Accepted',  'Scheduled', 'u-rec01','2026-08-31 17:11:00',NULL,NULL,NULL),
('d-38','pr-11','Scheduled', 'InProgress','u-doc04','2026-09-01 15:00:00',NULL,NULL,NULL),
('d-39','pr-11','InProgress','Completed', 'u-doc04','2026-09-01 16:00:00',NULL,NULL,'Two shades lighter.'),
('d-40','pr-12',NULL,        'Proposed',  'u-doc04','2026-08-31 17:00:00',NULL,NULL,NULL),
('d-41','pr-12','Proposed',  'Accepted',  'u-rec01','2026-08-31 17:10:00',NULL,NULL,NULL),
('d-42','pr-12','Accepted',  'Scheduled', 'u-rec01','2026-08-31 17:11:00',NULL,NULL,NULL),
('d-43','pr-12','Scheduled', 'InProgress','u-doc04','2026-09-01 16:00:00',NULL,NULL,NULL),
('d-44','pr-12','InProgress','Completed', 'u-doc04','2026-09-01 16:25:00',NULL,NULL,'Scale and polish completed.');

-- --------------------------------------------------------------- proposals --
INSERT INTO special_procedure_proposal (id, treatment_plan_id, proposed_by, service_category_id, clinical_justification, estimated_cost, status, reviewed_by, reviewed_at, review_note) VALUES
('sp-01','tp-01','u-doc01','sc-07','Non-restorable #46 already extracted. Bone volume adequate on CBCT; implant is the only fixed option that avoids preparing sound adjacent teeth.',25000000,'Approved','u-mgr01','2026-08-25 11:00:00','Approved. Osstem fixture, standard rate.'),
('sp-02','tp-02','u-doc04','sc-08','Class II div 1 with 8mm overjet and lip incompetence. Fixed appliance indicated; patient is 23 and growth is complete.',55000000,'Pending',NULL,NULL,NULL);

INSERT INTO discount_proposal (id, treatment_plan_id, proposed_by, discount_type, discount_value, reason, status, reviewed_by, reviewed_at, review_note) VALUES
('dp-01','tp-03','u-doc01','Percentage',10,'Long-standing patient, third course of treatment this year. Requesting a goodwill discount on the crown.','Approved','u-mgr01','2026-08-29 08:30:00','Approved at 10%.');

COMMIT;
