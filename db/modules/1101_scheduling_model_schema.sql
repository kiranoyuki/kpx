-- =============================================================================
-- KPX — MODULE 11: The scheduling model
--
-- Source of truth: Design/core-entities/scheduling-model.md
-- Depends on:      1 (staff_profile), 2 (service_category, chair_type)
--
-- "A service determines what resources and duration are needed. An appointment
--  reserves those resources for a time interval."
--
-- This module is the additive half of that model: what a service needs, who can
-- perform it, and when the clinic is open. The appointment side — service_id,
-- appointment_resource, appointment_reason, and splitting scheduled_at — is
-- module 12, because it changes existing tables and views rather than adding to
-- them.
--
-- Nothing here is read by the old scheduling views, so the two can coexist while
-- module 12 is built.
-- =============================================================================

PRAGMA foreign_keys = ON;


-- -----------------------------------------------------------------------------
-- Services carry their own scheduling rules
--
-- Duration and who may book are properties of the service, not branches in a
-- handler. booking_policy is what stops the patient app offering an implant
-- surgery; adding a service the public may book is then a row, not a deploy.
-- -----------------------------------------------------------------------------
ALTER TABLE service_category ADD COLUMN default_duration_minutes INTEGER;

ALTER TABLE service_category ADD COLUMN booking_policy TEXT NOT NULL DEFAULT 'StaffBookable';

-- A service the public may book must say how long it takes, or availability has
-- nothing to slice the day into.
CREATE VIEW v_service_bookable_check AS
SELECT id, name, booking_policy, default_duration_minutes,
       CASE
         WHEN booking_policy = 'PatientBookable' AND default_duration_minutes IS NULL
           THEN 'PatientBookable with no duration'
         WHEN default_duration_minutes IS NOT NULL AND default_duration_minutes <= 0
           THEN 'duration must be positive'
         ELSE 'ok'
       END AS problem
FROM service_category;


-- -----------------------------------------------------------------------------
-- What a service may be performed in
--
-- A list of ALLOWED resource types, not one required type. The OR is the point:
-- a consultation fits a consult room or an ordinary chair, and forcing it into
-- the consult room leaves four chairs idle.
--
-- service_category.required_chair_type_id stays for now and is superseded by
-- this table; module 12 drops it once nothing reads it.
-- -----------------------------------------------------------------------------
CREATE TABLE service_resource_requirement (
    id                  TEXT PRIMARY KEY,
    service_category_id TEXT NOT NULL REFERENCES service_category(id) ON DELETE CASCADE,
    -- chair_type is the resource type; module 12 renames the table, not the idea
    chair_type_id       TEXT NOT NULL REFERENCES chair_type(id) ON DELETE RESTRICT,
    -- how many of this type at once. Two is a real case: an assistant's chair,
    -- or a room plus the imaging equipment in it.
    quantity            INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    display_order       INTEGER NOT NULL DEFAULT 0,

    -- one row per (service, type): quantity says how many, not repetition
    CONSTRAINT uq_srr_service_type UNIQUE (service_category_id, chair_type_id)
);


-- -----------------------------------------------------------------------------
-- Who can perform what
--
-- Not inferred from role. `role` cannot express that one doctor places implants
-- and another does not, and availability has to ask exactly that question before
-- it offers a time.
-- -----------------------------------------------------------------------------
CREATE TABLE provider_service_capability (
    id                  TEXT PRIMARY KEY,
    staff_id            TEXT NOT NULL REFERENCES staff_profile(id) ON DELETE CASCADE,
    service_category_id TEXT NOT NULL REFERENCES service_category(id) ON DELETE CASCADE,
    -- kept as a row rather than deleted, so withdrawing a capability leaves a trace
    is_enabled          INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0,1)),
    note                TEXT,

    CONSTRAINT uq_psc_staff_service UNIQUE (staff_id, service_category_id)
);


-- -----------------------------------------------------------------------------
-- When the clinic is open
--
-- Closes the gap conventions.md §13 has carried from the start: booking needs
-- doctor free, resource free, AND clinic open, and the third had no entity.
--
-- Same shape as doctor_schedule deliberately — a recurring weekday, or a dated
-- exception that overrides it. A public holiday is a row with is_open = 0, not a
-- special case in code.
-- -----------------------------------------------------------------------------
CREATE TABLE clinic_hours (
    id           TEXT PRIMARY KEY,
    day_of_week  INTEGER CHECK (day_of_week BETWEEN 0 AND 6),   -- 0 = Sunday
    date         TEXT,                                          -- a dated exception
    opens_at     TEXT,                                          -- 'HH:MM', clinic time
    closes_at    TEXT,
    is_open      INTEGER NOT NULL DEFAULT 1 CHECK (is_open IN (0,1)),
    note         TEXT,

    -- exactly one addressing mode, as doctor_schedule does
    CONSTRAINT ck_hours_one_mode CHECK ((day_of_week IS NULL) <> (date IS NULL)),
    -- an open day states its hours; a closed one states none
    CONSTRAINT ck_hours_open_has_window CHECK (
        (is_open = 0 AND opens_at IS NULL AND closes_at IS NULL) OR
        (is_open = 1 AND opens_at IS NOT NULL AND closes_at IS NOT NULL)),
    CONSTRAINT ck_hours_closes_after_opens CHECK (closes_at IS NULL OR closes_at > opens_at),
    CONSTRAINT uq_hours_weekday UNIQUE (day_of_week),
    CONSTRAINT uq_hours_date    UNIQUE (date)
);


CREATE INDEX idx_srr_service   ON service_resource_requirement(service_category_id);
CREATE INDEX idx_srr_type      ON service_resource_requirement(chair_type_id);
CREATE INDEX idx_psc_staff     ON provider_service_capability(staff_id);
CREATE INDEX idx_psc_service   ON provider_service_capability(service_category_id, is_enabled);
CREATE INDEX idx_hours_date    ON clinic_hours(date);


-- =============================================================================
-- VIEWS
-- =============================================================================

-- What each service may be performed in, one row per allowed type.
CREATE VIEW v_service_requirements AS
SELECT s.id AS service_id, s.name AS service, s.booking_policy,
       s.default_duration_minutes AS minutes,
       ct.name AS allows_resource_type, r.quantity
FROM service_category s
LEFT JOIN service_resource_requirement r ON r.service_category_id = s.id
LEFT JOIN chair_type ct ON ct.id = r.chair_type_id
WHERE s.is_active = 1
ORDER BY s.display_order, r.display_order;

-- Who may perform what, for the availability engine and for review.
CREATE VIEW v_provider_capabilities AS
SELECT u.full_name AS provider, u.role, sp.employment_status, s.name AS service, c.is_enabled
FROM provider_service_capability c
JOIN staff_profile sp   ON sp.id = c.staff_id
JOIN app_user u         ON u.id = sp.user_id
JOIN service_category s ON s.id = c.service_category_id
ORDER BY u.full_name, s.display_order;

-- A service nobody can perform can never be offered a time. Expect zero rows
-- for anything PatientBookable.
CREATE VIEW v_service_without_provider AS
SELECT s.id, s.name, s.booking_policy
FROM service_category s
WHERE s.is_active = 1
  AND NOT EXISTS (SELECT 1 FROM provider_service_capability c
                  WHERE c.service_category_id = s.id AND c.is_enabled = 1);

-- A service with no allowed resource type likewise. Expect zero rows.
CREATE VIEW v_service_without_resource AS
SELECT s.id, s.name
FROM service_category s
WHERE s.is_active = 1
  AND NOT EXISTS (SELECT 1 FROM service_resource_requirement r
                  WHERE r.service_category_id = s.id);
