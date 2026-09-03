-- =============================================================================
-- KPX — MODULE 5 seed: Clinical Record
--
-- 6 health records, 18 tooth conditions, 15 procedure_tooth rows,
-- 4 media items, 8 sessions.
--
-- The two many-to-many directions are both demonstrated:
--   · ONE FINDING, TWO PROCEDURES — deep caries on 36 needs a root canal AND
--     then a crown. Both point at the same condition.
--   · ONE PROCEDURE, MANY FINDINGS — a single scaling clears calculus on six
--     teeth. Six rows, each addressing its own tooth's finding.
--
-- Also: a finding charted mid-treatment (not at an exam), a condition marked
-- EnteredInError rather than deleted, and sessions worked by different staff.
-- =============================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- ------------------------------------------------------------ health records --
INSERT INTO health_record (id, patient_id, blood_type, allergies, current_medications, medical_conditions, dental_history, last_updated_by, last_updated_at) VALUES
('hr-01','pp-01','O+','None known','Amlodipine 5mg','Hypertension, controlled','Regular attender. Lower right molar failing for two years.','u-doc01','2026-08-25 09:20:00'),
('hr-02','pp-02','A+','Penicillin — rash','None','None','Orthodontic assessment only. No restorative history.','u-doc04','2026-08-25 10:05:00'),
('hr-03','pp-03','B+','None known','Metformin 500mg','Type 2 diabetes','Irregular attender. Presented with pain on #36.','u-doc01','2026-08-28 09:35:00'),
('hr-04','pp-04','O-','Latex — contact dermatitis','None','None','Six-monthly recall, good compliance.','u-doc04','2026-09-02 14:05:00'),
('hr-05','pp-05','A-','None known','None','None','Staff member. Wants whitening before a family event.','u-doc04','2026-08-31 17:05:00'),
('hr-06','pp-06','AB+','None known','None','None','Former staff. Retains care at the clinic.','u-rec01','2026-04-11 09:35:00');

-- ---------------------------------------------------------- tooth conditions --
-- pp-01: the implant case. Baseline exam charted during the consultation pr-01.
INSERT INTO tooth_condition (id, patient_id, tooth_code, surfaces, condition_type, status, severity, note, observed_during_procedure_id, observed_by, observed_at, resolved_at) VALUES
('tc-01','pp-01','46',NULL, 'Fracture','Resolved','Severe','Non-restorable vertical root fracture. Extraction indicated.','pr-01','u-doc01','2026-08-25 09:20:00','2026-08-28 14:50:00'),
('tc-02','pp-01','46',NULL, 'Missing', 'Active',  NULL,    'Extracted 2026-08-28, socket preserved for implant.',        'pr-02','u-doc01','2026-08-28 14:50:00',NULL),
('tc-03','pp-01','16','MO', 'Filling',  'Active', NULL,    'Existing amalgam, sound.',                                   'pr-01','u-doc01','2026-08-25 09:20:00',NULL),
('tc-04','pp-01','26','O',  'Caries',   'Monitoring','Mild','Early enamel lesion. Watch at next recall.',                'pr-01','u-doc01','2026-08-25 09:20:00',NULL),

-- pp-02: orthodontic assessment, minimal restorative findings
('tc-05','pp-02','11',NULL, 'Discolouration','Monitoring','Mild','Mild fluorosis, patient unconcerned.','pr-05','u-doc04','2026-08-25 10:05:00',NULL),
('tc-06','pp-02','38',NULL, 'Impacted','Active','Moderate','Mesioangular impaction. Review after appliance therapy.','pr-05','u-doc04','2026-08-25 10:05:00',NULL),

-- pp-03: THE ONE-FINDING-TWO-PROCEDURES CASE.
-- Deep caries on 36 needs a root canal AND a crown.
('tc-07','pp-03','36','MOD','Caries','Active','Severe','Deep caries into the pulp chamber. Needs endodontics, then a crown to protect the remaining structure.','pr-07','u-doc01','2026-08-28 09:35:00',NULL),
('tc-08','pp-03','37','O',  'Caries','Active','Mild','Small occlusal lesion. Declined at first offer, accepted at review.','pr-07','u-doc01','2026-08-28 09:35:00',NULL),
-- charted MID-TREATMENT, not at an exam: spotted while working on 36
('tc-09','pp-03','35',NULL, 'Sensitivity','Monitoring','Mild','Reported during the root canal appointment. No caries visible.','pr-07','u-doc01','2026-08-28 09:50:00',NULL),
-- entered in error: charted on the wrong tooth, corrected by a new row, NOT deleted
('tc-10','pp-03','34','O',  'Caries','EnteredInError',NULL,'Charted on 34 in error; the lesion is on 37. Superseded by tc-08.','pr-07','u-doc01','2026-08-28 09:36:00',NULL),

-- pp-04: THE ONE-PROCEDURE-MANY-FINDINGS CASE.
-- Calculus on six teeth, all cleared by a single scaling.
('tc-11','pp-04','31',NULL,'Attrition','Active','Mild','Generalised calculus, lower anteriors.','pr-10','u-doc04','2026-09-02 14:05:00',NULL),
('tc-12','pp-04','32',NULL,'Attrition','Active','Mild','Generalised calculus.','pr-10','u-doc04','2026-09-02 14:05:00',NULL),
('tc-13','pp-04','41',NULL,'Attrition','Active','Mild','Generalised calculus.','pr-10','u-doc04','2026-09-02 14:05:00',NULL),
('tc-14','pp-04','42',NULL,'Attrition','Active','Mild','Generalised calculus.','pr-10','u-doc04','2026-09-02 14:05:00',NULL),
('tc-15','pp-04','16',NULL,'Attrition','Active','Mild','Calculus, upper right molar.','pr-10','u-doc04','2026-09-02 14:05:00',NULL),
('tc-16','pp-04','26',NULL,'Attrition','Active','Mild','Calculus, upper left molar.','pr-10','u-doc04','2026-09-02 14:05:00',NULL),

-- pp-05 and pp-06: staff patients
('tc-17','pp-05','11',NULL,'Discolouration','Active','Moderate','Extrinsic staining, coffee. Whitening requested.','pr-11','u-doc04','2026-08-31 17:05:00',NULL),
('tc-18','pp-06','47','MO','Filling','Active',NULL,'Existing composite, placed elsewhere. Sound.',NULL,'u-rec01','2026-04-11 09:35:00',NULL);

-- --------------------------------------------------------- procedure ↔ tooth --
INSERT INTO procedure_tooth (id, procedure_id, tooth_code, surfaces, addresses_condition_id, role, note) VALUES
('pt-01','pr-02','46',NULL,'tc-01',NULL,'Extraction of the fractured tooth.'),
('pt-02','pr-03','46',NULL,'tc-02',NULL,'Implant into the preserved socket.'),
('pt-03','pr-04','46',NULL,'tc-02',NULL,'Crown on the implant fixture.'),
-- ONE FINDING (tc-07), TWO PROCEDURES: the root canal and then the crown
('pt-04','pr-07','36','MOD','tc-07',NULL,'Endodontic access through the caries.'),
('pt-05','pr-08','36',NULL, 'tc-07',NULL,'Crown to protect the endodontically treated tooth.'),
('pt-06','pr-09','37','O',  'tc-08',NULL,'Composite restoration.'),
-- ONE PROCEDURE (pr-10 scaling), SIX FINDINGS: one row per tooth
('pt-07','pr-10','31',NULL,'tc-11',NULL,NULL),
('pt-08','pr-10','32',NULL,'tc-12',NULL,NULL),
('pt-09','pr-10','41',NULL,'tc-13',NULL,NULL),
('pt-10','pr-10','42',NULL,'tc-14',NULL,NULL),
('pt-11','pr-10','16',NULL,'tc-15',NULL,NULL),
('pt-12','pr-10','26',NULL,'tc-16',NULL,NULL);

-- ------------------------------------------------------------------- media --
INSERT INTO patient_media (id, patient_id, type, stage, file_url, taken_at, uploaded_by, procedure_id, notes) VALUES
('pm-01','pp-01','CBCT',      'Before','s3://kpx/media/pp-01/cbct-20260825.dcm','2026-08-25','u-ast01','pr-01','Bone volume assessment for #46 implant.'),
('pm-02','pp-01','Xray',      'After', 's3://kpx/media/pp-01/pa-46-20260828.jpg','2026-08-28','u-ast01','pr-02','Post-extraction periapical.'),
('pm-03','pp-03','Xray',      'Before','s3://kpx/media/pp-03/pa-36-20260828.jpg','2026-08-28','u-ast01','pr-07','Periapical #36 showing pulpal involvement.'),
('pm-04','pp-05','Photograph','Before','s3://kpx/media/pp-05/shade-20260831.jpg','2026-08-31','u-ast01','pr-11','Baseline shade for whitening.');

-- ---------------------------------------------------------------- sessions --
-- billable_amount is NULL throughout: nothing has been invoiced, so no price
-- has bound. Module 6 fills these as invoice lines are created.
INSERT INTO procedure_session (id, procedure_id, session_number, appointment_id, status, performed_by, assistant_id, completed_at, progress_note, vitals, next_step_note) VALUES
('ps-01','pr-01',1,'ap-01','Completed','st-doc01',NULL,      '2026-08-25 09:45:00','Full exam, CBCT reviewed. Staged implant plan agreed.','{"bp":"138/86","pulse":76}',NULL),
('ps-02','pr-02',1,NULL,   'Completed','st-doc01','st-ast01','2026-08-28 14:50:00','Atraumatic extraction #46. Socket preserved with graft.','{"bp":"142/88","pulse":82}','Review in 8 weeks before fixture placement.'),
-- pr-03 is a TWO-session procedure: fixture now, abutment later
('ps-03','pr-03',1,'ap-05','Scheduled', 'st-doc01','st-ast01',NULL,NULL,NULL,'Fixture placement.'),
('ps-04','pr-05',1,'ap-02','Completed','st-doc04',NULL,      '2026-08-25 10:00:00','Records, photographs and study models taken.',NULL,NULL),
('ps-05','pr-07',1,NULL,   'Scheduled', 'st-doc01','st-ast01',NULL,NULL,NULL,'Single-visit RCT #36.'),
-- pr-10 scaling, delivered by a different doctor and the intern assistant
('ps-06','pr-10',1,'ap-06','Completed','st-doc04','st-ast01','2026-09-02 14:30:00','Full-mouth scale and polish. OHI given.','{"bp":"124/78","pulse":68}','Recall in six months.');

COMMIT;
