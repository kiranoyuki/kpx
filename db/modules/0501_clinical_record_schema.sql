-- =============================================================================
-- KPX — MODULE 5: Clinical Record
-- surface_combination · health_record · tooth_condition
-- procedure_tooth · patient_media · procedure_session
--
-- Source of truth: Design/core-entities/entities.md
-- Build order:     Design/build-plan.md  (module 5 of 9; depends on 1–4)
--
-- The odontogram and the record of work actually done.
-- =============================================================================

PRAGMA foreign_keys = ON;


-- -----------------------------------------------------------------------------
-- Every canonical surface subset, per tooth type. 62 rows, generated.
--
-- Surfaces are written in canonical order M · O/I · D · B · L, so a three-surface
-- filling is always 'MOD' and never 'DOM' — one spelling per set, so it can be
-- compared and counted. Validating that in a trigger means walking the string
-- and checking both membership and order, which is easy to get subtly wrong.
-- A lookup table makes it exact: the surfaces are valid iff the row exists.
-- -----------------------------------------------------------------------------
CREATE TABLE surface_combination (
    valid_surfaces TEXT NOT NULL CHECK (valid_surfaces IN ('MIDBL','MODBL')),
    combo          TEXT NOT NULL,
    PRIMARY KEY (valid_surfaces, combo)
);

INSERT INTO surface_combination (valid_surfaces, combo) VALUES
('MIDBL','M'),
('MIDBL','I'),
('MIDBL','D'),
('MIDBL','B'),
('MIDBL','L'),
('MIDBL','MI'),
('MIDBL','MD'),
('MIDBL','MB'),
('MIDBL','ML'),
('MIDBL','ID'),
('MIDBL','IB'),
('MIDBL','IL'),
('MIDBL','DB'),
('MIDBL','DL'),
('MIDBL','BL'),
('MIDBL','MID'),
('MIDBL','MIB'),
('MIDBL','MIL'),
('MIDBL','MDB'),
('MIDBL','MDL'),
('MIDBL','MBL'),
('MIDBL','IDB'),
('MIDBL','IDL'),
('MIDBL','IBL'),
('MIDBL','DBL'),
('MIDBL','MIDB'),
('MIDBL','MIDL'),
('MIDBL','MIBL'),
('MIDBL','MDBL'),
('MIDBL','IDBL'),
('MIDBL','MIDBL'),
('MODBL','M'),
('MODBL','O'),
('MODBL','D'),
('MODBL','B'),
('MODBL','L'),
('MODBL','MO'),
('MODBL','MD'),
('MODBL','MB'),
('MODBL','ML'),
('MODBL','OD'),
('MODBL','OB'),
('MODBL','OL'),
('MODBL','DB'),
('MODBL','DL'),
('MODBL','BL'),
('MODBL','MOD'),
('MODBL','MOB'),
('MODBL','MOL'),
('MODBL','MDB'),
('MODBL','MDL'),
('MODBL','MBL'),
('MODBL','ODB'),
('MODBL','ODL'),
('MODBL','OBL'),
('MODBL','DBL'),
('MODBL','MODB'),
('MODBL','MODL'),
('MODBL','MOBL'),
('MODBL','MDBL'),
('MODBL','ODBL'),
('MODBL','MODBL');


-- Medical history and baseline health. One per patient.
CREATE TABLE health_record (
    id                  TEXT PRIMARY KEY,
    patient_id          TEXT NOT NULL UNIQUE REFERENCES patient_profile(id) ON DELETE CASCADE,
    blood_type          TEXT,
    allergies           TEXT,
    current_medications TEXT,
    medical_conditions  TEXT,
    dental_history      TEXT,
    last_updated_by     TEXT REFERENCES app_user(id),
    last_updated_at     TEXT
);


-- A clinical finding on one tooth. A patient's Active rows ARE their odontogram.
CREATE TABLE tooth_condition (
    id             TEXT PRIMARY KEY,
    patient_id     TEXT NOT NULL REFERENCES patient_profile(id) ON DELETE CASCADE,
    tooth_code     TEXT NOT NULL REFERENCES tooth(code),
    -- canonical-ordered subset of that tooth's valid_surfaces; NULL for
    -- whole-tooth findings
    surfaces       TEXT,
    condition_type TEXT NOT NULL CHECK (condition_type IN (
                       -- pathology
                       'Caries','Fracture','Attrition','Erosion','Abrasion',
                       'Abscess','Mobility','Sensitivity','Discolouration',
                       -- existing restoration
                       'Filling','Crown','Veneer','BridgeAbutment','BridgePontic',
                       'Implant','RootCanalTreated','Denture',
                       -- absence and eruption
                       'Missing','Unerupted','Impacted','Supernumerary')),
    status         TEXT NOT NULL DEFAULT 'Active'
                       CHECK (status IN ('Active','Monitoring','Resolved','EnteredInError')),
    severity       TEXT CHECK (severity IS NULL OR severity IN ('Mild','Moderate','Severe')),
    note           TEXT,
    -- the visit these findings were charted at, usually a Consultation. This is
    -- what groups a whole exam without needing an examination entity.
    observed_during_procedure_id TEXT REFERENCES treatment_procedure(id) ON DELETE SET NULL,
    observed_by    TEXT NOT NULL REFERENCES app_user(id),
    observed_at    TEXT NOT NULL DEFAULT (datetime('now')),
    resolved_at    TEXT,

    CONSTRAINT ck_cond_resolved_has_date CHECK (
        (status = 'Resolved') = (resolved_at IS NOT NULL)),
    -- a whole-tooth finding cannot name surfaces
    CONSTRAINT ck_cond_wholetooth_no_surfaces CHECK (
        condition_type NOT IN ('Missing','Unerupted','Impacted','Supernumerary',
                               'Implant','Crown','Denture','RootCanalTreated',
                               'BridgeAbutment','BridgePontic','Mobility')
        OR surfaces IS NULL)
);


-- Which teeth and surfaces a procedure addresses, and WHY.
CREATE TABLE procedure_tooth (
    id                     TEXT PRIMARY KEY,
    procedure_id           TEXT NOT NULL REFERENCES treatment_procedure(id) ON DELETE CASCADE,
    tooth_code             TEXT NOT NULL REFERENCES tooth(code),
    surfaces               TEXT,
    -- the finding this work is treating. Because the FK sits here, on the
    -- (procedure x tooth) junction, the relationship is many-to-many BOTH ways:
    -- a root canal and a crown can point at the same caries, and one scaling
    -- can have twenty rows each addressing its own tooth's calculus.
    addresses_condition_id TEXT REFERENCES tooth_condition(id) ON DELETE SET NULL,
    role                   TEXT CHECK (role IS NULL OR role IN ('Primary','Abutment','Pontic')),
    note                   TEXT,
    UNIQUE (procedure_id, tooth_code)
);


CREATE TABLE patient_media (
    id           TEXT PRIMARY KEY,
    patient_id   TEXT NOT NULL REFERENCES patient_profile(id) ON DELETE CASCADE,
    type         TEXT NOT NULL CHECK (type IN ('Xray','CBCT','Photograph','Other')),
    stage        TEXT CHECK (stage IS NULL OR stage IN ('Before','During','After')),
    file_url     TEXT NOT NULL,
    taken_at     TEXT,
    uploaded_by  TEXT NOT NULL REFERENCES app_user(id),
    procedure_id TEXT REFERENCES treatment_procedure(id) ON DELETE SET NULL,
    notes        TEXT
);


-- One visit's work on a procedure — and the unit the clinic is paid at.
-- Every procedure has at least one, so the billing rule has no special cases:
-- one completed session, one invoice line.
CREATE TABLE procedure_session (
    id              TEXT PRIMARY KEY,
    procedure_id    TEXT NOT NULL REFERENCES treatment_procedure(id) ON DELETE CASCADE,
    session_number  INTEGER NOT NULL CHECK (session_number > 0),
    appointment_id  TEXT REFERENCES appointment(id) ON DELETE SET NULL,
    status          TEXT NOT NULL DEFAULT 'Scheduled'
                        CHECK (status IN ('Scheduled','Completed','Cancelled')),
    -- staff sit HERE, not on the procedure: three visits may be worked by
    -- different doctors and different assistants, and commission follows
    -- whoever was actually there
    performed_by    TEXT NOT NULL REFERENCES staff_profile(id),
    assistant_id    TEXT REFERENCES staff_profile(id),
    -- NULL until the procedure is priced. unit_price binds when a procedure is
    -- first invoiced (module 6), so a session completing before that has no
    -- amount yet — module 6 fills it as the invoice line is created.
    billable_amount NUMERIC CHECK (billable_amount IS NULL OR billable_amount >= 0),
    completed_at    TEXT,
    progress_note   TEXT,
    vitals          TEXT CHECK (vitals IS NULL OR json_valid(vitals)),
    next_step_note  TEXT,

    UNIQUE (procedure_id, session_number),
    CONSTRAINT ck_session_completed_has_time CHECK (
        (status = 'Completed') = (completed_at IS NOT NULL))
);


CREATE INDEX idx_cond_patient      ON tooth_condition(patient_id, status);
CREATE INDEX idx_cond_tooth        ON tooth_condition(tooth_code);
CREATE INDEX idx_cond_observed     ON tooth_condition(observed_during_procedure_id);
CREATE INDEX idx_ptooth_procedure  ON procedure_tooth(procedure_id);
CREATE INDEX idx_ptooth_tooth      ON procedure_tooth(tooth_code);
CREATE INDEX idx_ptooth_condition  ON procedure_tooth(addresses_condition_id);
CREATE INDEX idx_media_patient     ON patient_media(patient_id);
CREATE INDEX idx_media_procedure   ON patient_media(procedure_id);
CREATE INDEX idx_session_procedure ON procedure_session(procedure_id, session_number);
CREATE INDEX idx_session_appt      ON procedure_session(appointment_id);
CREATE INDEX idx_session_performer ON procedure_session(performed_by);
CREATE INDEX idx_session_status    ON procedure_session(status);


-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- Surfaces must be a canonical subset of what that tooth physically has.
-- An occlusal surface on an incisor is nonsense and is refused.
CREATE TRIGGER trg_cond_surfaces_valid BEFORE INSERT ON tooth_condition
WHEN NEW.surfaces IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'surfaces are not a canonical subset of this tooth''s valid surfaces')
    WHERE NOT EXISTS (
        SELECT 1 FROM surface_combination sc
        JOIN tooth t ON t.code = NEW.tooth_code
        WHERE sc.valid_surfaces = t.valid_surfaces AND sc.combo = NEW.surfaces);
END;

CREATE TRIGGER trg_ptooth_surfaces_valid BEFORE INSERT ON procedure_tooth
WHEN NEW.surfaces IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'surfaces are not a canonical subset of this tooth''s valid surfaces')
    WHERE NOT EXISTS (
        SELECT 1 FROM surface_combination sc
        JOIN tooth t ON t.code = NEW.tooth_code
        WHERE sc.valid_surfaces = t.valid_surfaces AND sc.combo = NEW.surfaces);
END;

-- A finding may only be addressed by work on the SAME patient.
CREATE TRIGGER trg_ptooth_condition_same_patient BEFORE INSERT ON procedure_tooth
WHEN NEW.addresses_condition_id IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'that finding belongs to a different patient')
    WHERE (SELECT c.patient_id FROM tooth_condition c WHERE c.id = NEW.addresses_condition_id)
       <> (SELECT tp.patient_id FROM treatment_procedure pr
           JOIN treatment_plan tp ON tp.id = pr.treatment_plan_id
           WHERE pr.id = NEW.procedure_id);

    SELECT RAISE(ABORT, 'that finding is on a different tooth')
    WHERE (SELECT c.tooth_code FROM tooth_condition c WHERE c.id = NEW.addresses_condition_id)
       <> NEW.tooth_code;
END;

-- A clinical record must show what was believed at the time: a finding entered
-- in error is marked EnteredInError, never deleted.
CREATE TRIGGER trg_cond_no_delete BEFORE DELETE ON tooth_condition
BEGIN
    SELECT RAISE(ABORT, 'tooth_condition is append-only: mark it EnteredInError instead');
END;

-- Work cannot happen on a procedure the patient has not agreed to.
CREATE TRIGGER trg_session_needs_accepted BEFORE INSERT ON procedure_session
BEGIN
    SELECT RAISE(ABORT, 'cannot open a session on a procedure that is not at least Accepted')
    WHERE (SELECT status FROM treatment_procedure WHERE id = NEW.procedure_id)
          NOT IN ('Accepted','Scheduled','InProgress','Completed');
END;


-- =============================================================================
-- VIEWS
-- =============================================================================

-- THE ODONTOGRAM. The chart draws three layers, and only two of them are the
-- patient's actual dental health — planned work is an overlay for the doctor to
-- read, never a fact about the tooth.
CREATE VIEW v_tooth_chart AS
-- layer 1 + 2: existing state and findings to treat
SELECT u.full_name AS patient, c.patient_id, t.code AS tooth, t.name AS tooth_name,
       CASE WHEN c.condition_type IN ('Filling','Crown','Veneer','Implant',
                                      'RootCanalTreated','Denture','BridgeAbutment','BridgePontic')
            THEN 'existing' ELSE 'finding' END AS layer,
       c.condition_type, COALESCE(c.surfaces,'whole tooth') AS surfaces,
       COALESCE(c.severity,'') AS severity, c.status, c.observed_at AS as_of
FROM tooth_condition c
JOIN tooth t            ON t.code = c.tooth_code
JOIN patient_profile pp ON pp.id = c.patient_id
JOIN app_user u         ON u.id = pp.user_id
WHERE c.status IN ('Active','Monitoring')
UNION ALL
-- layer 3: planned work. NOT the record — it is drawn, not charted.
SELECT u.full_name, tp.patient_id, t.code, t.name,
       'planned', sc.name, COALESCE(pt.surfaces,'whole tooth'), '',
       pr.status, NULL
FROM procedure_tooth pt
JOIN treatment_procedure pr ON pr.id = pt.procedure_id
JOIN treatment_plan tp      ON tp.id = pr.treatment_plan_id
JOIN patient_profile pp     ON pp.id = tp.patient_id
JOIN app_user u             ON u.id = pp.user_id
JOIN tooth t                ON t.code = pt.tooth_code
JOIN service_category sc    ON sc.id = pr.service_category_id
WHERE pr.status IN ('Proposed','Accepted','Scheduled')
ORDER BY patient, tooth, layer;

-- A finding and every procedure addressing it. Many-to-many in both directions.
CREATE VIEW v_finding_treatment AS
SELECT u.full_name AS patient, c.id AS condition_id, c.tooth_code AS tooth,
       c.condition_type, COALESCE(c.surfaces,'whole tooth') AS surfaces, c.status AS finding_status,
       COUNT(pt.id) AS addressed_by_n,
       GROUP_CONCAT(sc.name || ' (' || pr.status || ')', ' + ') AS procedures
FROM tooth_condition c
JOIN patient_profile pp ON pp.id = c.patient_id
JOIN app_user u         ON u.id = pp.user_id
LEFT JOIN procedure_tooth pt      ON pt.addresses_condition_id = c.id
LEFT JOIN treatment_procedure pr  ON pr.id = pt.procedure_id
LEFT JOIN service_category sc     ON sc.id = pr.service_category_id
WHERE c.status <> 'EnteredInError'
GROUP BY c.id
ORDER BY addressed_by_n DESC, u.full_name, c.tooth_code;

-- What happened at each visit, and who did it.
CREATE VIEW v_session_log AS
SELECT pu.full_name AS patient, sc.name AS service, s.session_number AS n,
       pr.planned_sessions AS of_n, s.status,
       du.full_name AS performed_by, COALESCE(au.full_name,'—') AS assistant,
       COALESCE(a.scheduled_at,'—') AS visit, s.completed_at,
       COALESCE(CAST(s.billable_amount AS TEXT),'not yet priced') AS billable
FROM procedure_session s
JOIN treatment_procedure pr ON pr.id = s.procedure_id
JOIN treatment_plan tp      ON tp.id = pr.treatment_plan_id
JOIN patient_profile pp     ON pp.id = tp.patient_id
JOIN app_user pu            ON pu.id = pp.user_id
JOIN service_category sc    ON sc.id = pr.service_category_id
JOIN staff_profile sd       ON sd.id = s.performed_by
JOIN app_user du            ON du.id = sd.user_id
LEFT JOIN staff_profile sa  ON sa.id = s.assistant_id
LEFT JOIN app_user au       ON au.id = sa.user_id
LEFT JOIN appointment a     ON a.id = s.appointment_id
ORDER BY pu.full_name, sc.name, s.session_number;
