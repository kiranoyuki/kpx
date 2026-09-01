-- =============================================================================
-- KPX — MODULE 1: People & Access
-- app_user · staff_profile · patient_profile
--
-- Source of truth: Design/core-entities/entities.md
-- Build order:     Design/build-plan.md  (module 1 of 9; depends on nothing)
-- =============================================================================
--
-- app_user is a PERSON record, not a login. Every human has exactly one row.
-- Identity lives here once; the two profiles hold only employment or care data
-- and carry no names.
--
--   Portal access is granted by PROFILE, never by role:
--     PatientProfile exists                          -> patient portal
--     StaffProfile employment_status Intern|Active   -> staff portal
--   role then governs permissions *inside* the staff portal.
--
-- Authentication is deliberately not modelled: no credential columns exist.
-- Patients will identify with full_name + phone + national_id, or a one-time
-- code to phone. Both read columns already present here, so credential storage
-- can be designed later without disturbing this table.
--
-- CONVENTIONS  ids TEXT (UUID) · timestamps TEXT ISO-8601 · dates TEXT
--              booleans INTEGER 0/1 · enums TEXT + CHECK
-- Foreign keys are OFF by default in SQLite: every connection must issue
--     PRAGMA foreign_keys = ON;
-- =============================================================================

PRAGMA foreign_keys = ON;


CREATE TABLE app_user (
    id             TEXT PRIMARY KEY,

    -- identity, known from first contact
    full_name      TEXT NOT NULL,
    phone          TEXT NOT NULL,          -- dedup key at booking; also a sign-in field
    email          TEXT UNIQUE,            -- nullable: a walk-in may have none
    date_of_birth  TEXT,
    address        TEXT,
    -- Vietnamese CCCD, exactly 12 digits. TEXT, never numeric: it is an
    -- identifier rather than a quantity, and leading zeros are significant.
    national_id    TEXT UNIQUE,

    -- the PERSON's lifecycle — never their employment
    status         TEXT NOT NULL DEFAULT 'Provisional'
                       CHECK (status IN ('Provisional', 'Active', 'Inactive')),
    verified_at    TEXT,                   -- when identity was checked in person
    verified_by    TEXT REFERENCES app_user(id),

    role           TEXT NOT NULL CHECK (role IN (
                       'Manager', 'Doctor', 'Receptionist',
                       'Accountant', 'Assistant', 'Patient')),
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),

    -- CCCD is exactly 12 digits when present
    CONSTRAINT ck_user_cccd_12_digits CHECK (
        national_id IS NULL OR
        national_id GLOB '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    -- Active means a person physically verified them
    CONSTRAINT ck_user_active_is_verified CHECK (
        status <> 'Active' OR (verified_at IS NOT NULL AND verified_by IS NOT NULL)),
    -- a Provisional person has not been verified, by definition
    CONSTRAINT ck_user_provisional_unverified CHECK (
        status <> 'Provisional' OR (verified_at IS NULL AND verified_by IS NULL))
);


-- Employment data only. No name, phone or address — those live on app_user.
CREATE TABLE staff_profile (
    id                 TEXT PRIMARY KEY,
    user_id            TEXT NOT NULL UNIQUE REFERENCES app_user(id) ON DELETE CASCADE,
    join_date          TEXT NOT NULL,
    -- Intern is working and assignable; the difference from Active is terms,
    -- not access. OnLeave is not gone. Departed requires an end_date.
    employment_status  TEXT NOT NULL DEFAULT 'Active'
                           CHECK (employment_status IN ('Intern', 'Active', 'OnLeave', 'Departed')),
    end_date           TEXT,
    specialty          TEXT,               -- Doctor only
    license_number     TEXT,               -- Doctor only

    CONSTRAINT ck_staff_departed_has_end_date CHECK (
        (employment_status = 'Departed') = (end_date IS NOT NULL)),
    CONSTRAINT ck_staff_end_after_join CHECK (
        end_date IS NULL OR end_date >= join_date)
);


-- The care relationship, created on arrival — never at online-booking time.
-- Its existence is what makes someone a patient rather than a provisional booker.
CREATE TABLE patient_profile (
    id                 TEXT PRIMARY KEY,
    user_id            TEXT NOT NULL UNIQUE REFERENCES app_user(id) ON DELETE CASCADE,
    emergency_contact  TEXT,
    referral_source    TEXT,
    created_by         TEXT NOT NULL REFERENCES app_user(id),
    created_at         TEXT NOT NULL DEFAULT (datetime('now'))
);


CREATE INDEX idx_app_user_phone        ON app_user(phone);      -- dedup at booking
CREATE INDEX idx_app_user_status       ON app_user(status);
CREATE INDEX idx_app_user_name         ON app_user(full_name);
CREATE INDEX idx_app_user_verifier     ON app_user(verified_by);
CREATE INDEX idx_staff_employment      ON staff_profile(employment_status);
CREATE INDEX idx_patient_creator       ON patient_profile(created_by);


-- =============================================================================
-- VIEWS
-- =============================================================================

-- Who reaches which portal. Derived from profiles, never from role — which is
-- what lets one person hold both, and a departed doctor keep only the patient one.
CREATE VIEW v_portal_access AS
SELECT u.id, u.full_name, u.role, u.status,
       CASE WHEN u.status = 'Active' AND pp.id IS NOT NULL
            THEN 'yes' ELSE 'no' END AS patient_portal,
       CASE WHEN u.status = 'Active' AND sp.id IS NOT NULL
                 AND sp.employment_status IN ('Intern', 'Active')
            THEN 'yes' ELSE 'no' END AS staff_portal,
       COALESCE(sp.employment_status, '—') AS employment
FROM app_user u
LEFT JOIN staff_profile   sp ON sp.user_id = u.id
LEFT JOIN patient_profile pp ON pp.user_id = u.id;

-- Where every person sits in the identity lifecycle.
CREATE VIEW v_identity_funnel AS
SELECT u.status,
       COUNT(*)                                                      AS people,
       SUM(CASE WHEN u.national_id IS NOT NULL THEN 1 ELSE 0 END)    AS with_cccd,
       SUM(CASE WHEN u.email       IS NOT NULL THEN 1 ELSE 0 END)    AS with_email,
       SUM(CASE WHEN sp.id IS NOT NULL THEN 1 ELSE 0 END)            AS is_staff,
       SUM(CASE WHEN pp.id IS NOT NULL THEN 1 ELSE 0 END)            AS is_patient
FROM app_user u
LEFT JOIN staff_profile   sp ON sp.user_id = u.id
LEFT JOIN patient_profile pp ON pp.user_id = u.id
GROUP BY u.status;

-- People holding both profiles — staff who are also patients at their own clinic.
CREATE VIEW v_dual_profile AS
SELECT u.full_name, u.role, sp.employment_status, sp.id AS staff_id, pp.id AS patient_id
FROM app_user u
JOIN staff_profile   sp ON sp.user_id = u.id
JOIN patient_profile pp ON pp.user_id = u.id;
