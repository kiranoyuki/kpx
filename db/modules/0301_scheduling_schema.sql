-- =============================================================================
-- KPX — MODULE 3: Scheduling
-- doctor_schedule · appointment
--
-- Source of truth: Design/core-entities/entities.md
-- Build order:     Design/build-plan.md  (module 3 of 9; depends on 1 and 2)
--
-- appointment.person_id points at APP_USER, not patient_profile. An online
-- booking is made before the person has arrived and become a patient, so the
-- appointment must be able to reference a Provisional person. Conversion on
-- arrival is then one UPDATE plus one INSERT — this FK never changes, because
-- it was valid from the moment the booking was taken.
--
-- What was DONE at a visit is not here either. A visit routinely covers more
-- than one procedure (a filling and a scale in the same chair), so the work is
-- a list of procedure_session rows pointing back at the appointment. That
-- arrives with module 5.
-- =============================================================================

PRAGMA foreign_keys = ON;


-- A doctor's working availability: either a recurring weekday block, or a
-- one-off override for a specific date (a holiday, a conference).
CREATE TABLE doctor_schedule (
    id           TEXT PRIMARY KEY,
    doctor_id    TEXT NOT NULL REFERENCES staff_profile(id) ON DELETE CASCADE,
    day_of_week  INTEGER CHECK (day_of_week BETWEEN 0 AND 6),   -- 0 = Sunday
    date         TEXT,                                          -- one-off override
    start_time   TEXT NOT NULL,                                 -- 'HH:MM'
    end_time     TEXT NOT NULL,
    is_available INTEGER NOT NULL DEFAULT 1 CHECK (is_available IN (0,1)),
    note         TEXT,

    CONSTRAINT ck_sched_end_after_start CHECK (end_time > start_time),
    -- exactly one addressing mode: a recurring weekday OR a specific date
    CONSTRAINT ck_sched_one_mode CHECK ((day_of_week IS NULL) <> (date IS NULL))
);


CREATE TABLE appointment (
    id                TEXT PRIMARY KEY,
    person_id         TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    doctor_id         TEXT NOT NULL REFERENCES staff_profile(id),
    -- nullable so a chair can be assigned on the day. The cost of leaving it
    -- null is real: an appointment with no chair consumes no capacity, so a
    -- booking flow that skips it can quietly overbook the clinic.
    chair_id          TEXT REFERENCES chair(id),
    scheduled_at      TEXT NOT NULL,
    duration_minutes  INTEGER NOT NULL DEFAULT 30 CHECK (duration_minutes > 0),
    type              TEXT NOT NULL CHECK (type IN ('Consultation','Procedure','Followup')),
    status            TEXT NOT NULL DEFAULT 'Scheduled' CHECK (status IN (
                          'Scheduled','Confirmed','InProgress','Completed','Cancelled','NoShow')),
    -- Online bookings are the ones that create Provisional people and need the
    -- no-show reschedule chase
    booking_channel   TEXT NOT NULL DEFAULT 'FrontDesk'
                          CHECK (booking_channel IN ('Online','FrontDesk','Phone')),
    assistant_id      TEXT REFERENCES staff_profile(id),
    -- the receptionist whose follow-up contact produced this booking; a
    -- completed Followup with this set is their KPI credit
    followed_up_by    TEXT REFERENCES app_user(id),
    notes             TEXT,
    created_by        TEXT REFERENCES app_user(id),   -- NULL = self-booked online
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),

    CONSTRAINT ck_appt_selfbooked_is_online CHECK (
        created_by IS NOT NULL OR booking_channel = 'Online')
);


CREATE INDEX idx_sched_doctor      ON doctor_schedule(doctor_id);
CREATE INDEX idx_appt_person       ON appointment(person_id);
CREATE INDEX idx_appt_doctor_when  ON appointment(doctor_id, scheduled_at);
CREATE INDEX idx_appt_chair_when   ON appointment(chair_id, scheduled_at);
CREATE INDEX idx_appt_when         ON appointment(scheduled_at);
CREATE INDEX idx_appt_status       ON appointment(status);
CREATE INDEX idx_appt_channel      ON appointment(booking_channel, status);
CREATE INDEX idx_appt_followup     ON appointment(followed_up_by);


-- =============================================================================
-- TRIGGERS
--
-- PostgreSQL would express the overlap rules as EXCLUDE constraints. SQLite has
-- none, so they are triggers — which keeps them in the database rather than
-- trusting every future caller to remember.
--
-- Cancelled and NoShow appointments release their slot: they occupy nothing.
-- =============================================================================


-- =============================================================================
-- VIEWS
-- =============================================================================

-- Who is in which chair right now. Occupancy is DERIVED, never stored: an
-- appointment InProgress with a chair_id already says a patient is in it.
CREATE VIEW v_chair_occupancy AS
SELECT c.code AS chair, ct.name AS chair_type, c.status AS chair_status,
       CASE WHEN a.id IS NULL THEN 'free' ELSE 'in use' END AS occupancy,
       u.full_name AS patient, du.full_name AS doctor, a.scheduled_at
FROM chair c
JOIN chair_type ct ON ct.id = c.chair_type_id
LEFT JOIN appointment a ON a.chair_id = c.id AND a.status = 'InProgress'
LEFT JOIN app_user u    ON u.id = a.person_id
LEFT JOIN staff_profile sd ON sd.id = a.doctor_id
LEFT JOIN app_user du   ON du.id = sd.user_id
ORDER BY c.display_order;

-- The day sheet: everything booked for a given day, in time order.
CREATE VIEW v_day_sheet AS
SELECT date(a.scheduled_at)            AS day,
       time(a.scheduled_at)            AS at,
       a.duration_minutes              AS mins,
       COALESCE(c.code, '— unassigned —') AS chair,
       u.full_name                     AS person,
       u.status                        AS person_status,
       du.full_name                    AS doctor,
       a.type, a.status, a.booking_channel
FROM appointment a
JOIN app_user u        ON u.id = a.person_id
JOIN staff_profile sd  ON sd.id = a.doctor_id
JOIN app_user du       ON du.id = sd.user_id
LEFT JOIN chair c      ON c.id = a.chair_id
ORDER BY a.scheduled_at, c.display_order;

-- The reschedule chase: booked online, never arrived, still Provisional, and
-- with nothing else on the books.
CREATE VIEW v_reschedule_followup AS
SELECT u.id AS person_id, u.full_name, u.phone, u.email,
       a.id AS missed_appointment_id, a.scheduled_at AS missed_at, a.booking_channel,
       CAST(julianday('now') - julianday(a.scheduled_at) AS INTEGER) AS days_since
FROM app_user u
JOIN appointment a ON a.person_id = u.id AND a.status = 'NoShow'
WHERE u.status = 'Provisional'
  AND NOT EXISTS (SELECT 1 FROM appointment f
                  WHERE f.person_id = u.id
                    AND f.status IN ('Scheduled','Confirmed')
                    AND f.scheduled_at > a.scheduled_at)
ORDER BY a.scheduled_at DESC;

-- Advisory only: appointments sitting outside the doctor's stated availability.
-- Deliberately NOT a constraint — an emergency should never be blocked by the
-- rota, but the desk should be able to see when it happened.
CREATE VIEW v_appointment_off_roster AS
SELECT a.id, du.full_name AS doctor, a.scheduled_at, time(a.scheduled_at) AS at, a.status
FROM appointment a
JOIN staff_profile sd ON sd.id = a.doctor_id
JOIN app_user du      ON du.id = sd.user_id
WHERE a.status NOT IN ('Cancelled','NoShow')
  AND NOT EXISTS (
      SELECT 1 FROM doctor_schedule s
      WHERE s.doctor_id = a.doctor_id
        AND s.is_available = 1
        AND (s.date = date(a.scheduled_at)
             OR (s.date IS NULL AND s.day_of_week = CAST(strftime('%w', a.scheduled_at) AS INTEGER)))
        AND time(a.scheduled_at) >= s.start_time
        AND time(a.scheduled_at) <  s.end_time);
