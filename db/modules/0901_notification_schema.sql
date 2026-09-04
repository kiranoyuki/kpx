-- =============================================================================
-- KPX — MODULE 9: Notifications
-- notification
--
-- Source of truth: Design/core-entities/entities.md
-- Build order:     Design/build-plan.md  (module 9 of 9; reads from 1,3,4,6,7,8)
--
-- WHAT THIS RECORDS is what should be sent, to whom, and about what.
-- DELIVERY IS OUT OF SCOPE by decision: getting a message onto a phone is a
-- separate system (internal chat, SMS, Zalo) that will bring its own channel,
-- delivery status and retry policy. Those columns belong with that adapter, not
-- here. Appointment reminders and the no-show reschedule chase both wait on it.
--
-- The one thing this module must get right is the pointer: a notification is
-- almost always ABOUT something — an appointment, an invoice, a failed
-- treatment — and that reference is polymorphic, so SQLite cannot make it a
-- foreign key. It is validated by trigger instead, on insert and on update.
-- =============================================================================

PRAGMA foreign_keys = ON;


CREATE TABLE notification (
    id                  TEXT PRIMARY KEY,

    -- NULL sender = system-generated (a reminder, a low-stock alert)
    sender_id           TEXT REFERENCES app_user(id) ON DELETE SET NULL,

    -- exactly one of these: a person, or a role to broadcast to
    recipient_id        TEXT REFERENCES app_user(id) ON DELETE CASCADE,
    recipient_role      TEXT CHECK (recipient_role IS NULL OR recipient_role IN (
                            'Manager','Doctor','Receptionist','Accountant','Assistant','Patient')),

    type                TEXT NOT NULL CHECK (type IN ('Reminder','Page','Alert','Announcement')),
    title               TEXT NOT NULL,
    body                TEXT NOT NULL,

    -- the polymorphic pointer. Both columns or neither; the type is restricted
    -- to things that actually exist in this database, and trg_notif_target_exists
    -- checks the row is really there.
    related_entity_type TEXT CHECK (related_entity_type IS NULL OR related_entity_type IN (
                            'Appointment','TreatmentPlan','TreatmentProcedure','Invoice',
                            'TreatmentFailure','InventoryItem','Equipment','PayrollRecord')),
    related_entity_id   TEXT,

    is_read             INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0,1)),
    read_at             TEXT,
    sent_at             TEXT NOT NULL DEFAULT (datetime('now')),

    CONSTRAINT ck_notif_title CHECK (length(trim(title)) > 0),
    CONSTRAINT ck_notif_body  CHECK (length(trim(body))  > 0),

    -- A message goes to a person OR to a role, never both and never neither.
    CONSTRAINT ck_notif_recipient CHECK (
        (recipient_id IS NOT NULL AND recipient_role IS NULL) OR
        (recipient_id IS NULL     AND recipient_role IS NOT NULL)),

    -- Both halves of the pointer or neither. A type with no id points nowhere;
    -- an id with no type cannot be resolved to a table.
    CONSTRAINT ck_notif_target CHECK (
        (related_entity_type IS NULL     AND related_entity_id IS NULL) OR
        (related_entity_type IS NOT NULL AND related_entity_id IS NOT NULL)),

    -- Written as an equality this would pass a row with BOTH unset — the shape
    -- that hid a bug in module 6 and again in module 8. A CASE says what is meant.
    CONSTRAINT ck_notif_read CHECK (
        CASE is_read WHEN 1 THEN read_at IS NOT NULL ELSE read_at IS NULL END),

    -- A broadcast has no single reader, so it has no single read state. Per
    -- recipient read tracking needs a row per recipient, and that arrives with
    -- the delivery system; until then a broadcast simply stays unread.
    CONSTRAINT ck_notif_broadcast_unread CHECK (recipient_id IS NOT NULL OR is_read = 0),

    -- You page a PERSON, never a role: a page that everyone receives is one
    -- nobody answers. An announcement is the opposite — it is a broadcast.
    CONSTRAINT ck_notif_page_is_direct    CHECK (type <> 'Page'         OR recipient_id   IS NOT NULL),
    CONSTRAINT ck_notif_announce_is_broad CHECK (type <> 'Announcement' OR recipient_role IS NOT NULL),

    CONSTRAINT ck_notif_not_self CHECK (sender_id IS NULL OR sender_id <> recipient_id),
    CONSTRAINT ck_notif_read_after_sent CHECK (read_at IS NULL OR read_at >= sent_at)
);


CREATE INDEX idx_notif_recipient ON notification(recipient_id, sent_at DESC);
CREATE INDEX idx_notif_role      ON notification(recipient_role, sent_at DESC);
CREATE INDEX idx_notif_unread    ON notification(recipient_id) WHERE is_read = 0;
CREATE INDEX idx_notif_target    ON notification(related_entity_type, related_entity_id);


-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- The polymorphic pointer, enforced. Without this a notification could claim to
-- be about invoice 'inv-99' — and the UI would render an empty page with no
-- indication anything was wrong. SQLite cannot resolve a table name at runtime,
-- so each type is checked explicitly.
CREATE TRIGGER trg_notif_target_exists BEFORE INSERT ON notification
WHEN NEW.related_entity_type IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'the appointment this notification refers to does not exist')
    WHERE NEW.related_entity_type = 'Appointment'
      AND NOT EXISTS (SELECT 1 FROM appointment WHERE id = NEW.related_entity_id);

    SELECT RAISE(ABORT, 'the treatment plan this notification refers to does not exist')
    WHERE NEW.related_entity_type = 'TreatmentPlan'
      AND NOT EXISTS (SELECT 1 FROM treatment_plan WHERE id = NEW.related_entity_id);

    SELECT RAISE(ABORT, 'the procedure this notification refers to does not exist')
    WHERE NEW.related_entity_type = 'TreatmentProcedure'
      AND NOT EXISTS (SELECT 1 FROM treatment_procedure WHERE id = NEW.related_entity_id);

    SELECT RAISE(ABORT, 'the invoice this notification refers to does not exist')
    WHERE NEW.related_entity_type = 'Invoice'
      AND NOT EXISTS (SELECT 1 FROM invoice WHERE id = NEW.related_entity_id);

    SELECT RAISE(ABORT, 'the treatment failure this notification refers to does not exist')
    WHERE NEW.related_entity_type = 'TreatmentFailure'
      AND NOT EXISTS (SELECT 1 FROM treatment_failure WHERE id = NEW.related_entity_id);

    SELECT RAISE(ABORT, 'the inventory item this notification refers to does not exist')
    WHERE NEW.related_entity_type = 'InventoryItem'
      AND NOT EXISTS (SELECT 1 FROM inventory_item WHERE id = NEW.related_entity_id);

    SELECT RAISE(ABORT, 'the equipment this notification refers to does not exist')
    WHERE NEW.related_entity_type = 'Equipment'
      AND NOT EXISTS (SELECT 1 FROM equipment WHERE id = NEW.related_entity_id);

    SELECT RAISE(ABORT, 'the payroll record this notification refers to does not exist')
    WHERE NEW.related_entity_type = 'PayrollRecord'
      AND NOT EXISTS (SELECT 1 FROM payroll_record WHERE id = NEW.related_entity_id);
END;

-- A message that has been sent is a record of what was sent. Only its read
-- state may change afterwards — the same append-only discipline that governs
-- procedure_decision, invoice_line and commission_entry. Correcting a message
-- means sending another one.
CREATE TRIGGER trg_notif_content_immutable BEFORE UPDATE ON notification
WHEN COALESCE(NEW.sender_id,'')           <> COALESCE(OLD.sender_id,'')
  OR COALESCE(NEW.recipient_id,'')        <> COALESCE(OLD.recipient_id,'')
  OR COALESCE(NEW.recipient_role,'')      <> COALESCE(OLD.recipient_role,'')
  OR NEW.type                             <> OLD.type
  OR NEW.title                            <> OLD.title
  OR NEW.body                             <> OLD.body
  OR COALESCE(NEW.related_entity_type,'') <> COALESCE(OLD.related_entity_type,'')
  OR COALESCE(NEW.related_entity_id,'')   <> COALESCE(OLD.related_entity_id,'')
  OR NEW.sent_at                          <> OLD.sent_at
BEGIN
    SELECT RAISE(ABORT, 'a sent notification is a record of what was sent: only its read state may change');
END;

-- Marking read is the one permitted change, and it only goes one way. Every
-- audit so far has found an INSERT guard with no UPDATE twin, so this one is
-- written at the same time.
CREATE TRIGGER trg_notif_read_is_one_way BEFORE UPDATE OF is_read ON notification
WHEN OLD.is_read = 1 AND NEW.is_read = 0
BEGIN
    SELECT RAISE(ABORT, 'a notification cannot be un-read');
END;

-- A patient may only be told about their OWN care. Nothing enforced this, and
-- the seed promptly proved why it needed to: a no-show reminder went to the
-- wrong provisional patient, and an outstanding-balance notice named one
-- patient's treatment to another. Both were caught by v_pending_chases naming
-- different people than the notifications were addressed to.
--
-- Staff are exempt: being told about other people's appointments is the job.
-- The check is INSERT-only by design, not by omission — recipient and target
-- are both frozen by trg_notif_content_immutable, so there is no UPDATE that
-- could break it afterwards.
CREATE TRIGGER trg_notif_patient_sees_own BEFORE INSERT ON notification
WHEN NEW.recipient_id IS NOT NULL
     AND NEW.related_entity_type IN ('Appointment','Invoice','TreatmentPlan','TreatmentProcedure')
     AND NOT EXISTS (SELECT 1 FROM staff_profile WHERE user_id = NEW.recipient_id)
BEGIN
    SELECT RAISE(ABORT, 'that appointment belongs to another patient')
    WHERE NEW.related_entity_type = 'Appointment'
      AND (SELECT person_id FROM appointment WHERE id = NEW.related_entity_id) <> NEW.recipient_id;

    SELECT RAISE(ABORT, 'that invoice belongs to another patient')
    WHERE NEW.related_entity_type = 'Invoice'
      AND (SELECT pp.user_id FROM invoice i JOIN patient_profile pp ON pp.id = i.patient_id
            WHERE i.id = NEW.related_entity_id) <> NEW.recipient_id;

    SELECT RAISE(ABORT, 'that treatment plan belongs to another patient')
    WHERE NEW.related_entity_type = 'TreatmentPlan'
      AND (SELECT pp.user_id FROM treatment_plan tp JOIN patient_profile pp ON pp.id = tp.patient_id
            WHERE tp.id = NEW.related_entity_id) <> NEW.recipient_id;

    SELECT RAISE(ABORT, 'that procedure belongs to another patient')
    WHERE NEW.related_entity_type = 'TreatmentProcedure'
      AND (SELECT pp.user_id FROM treatment_procedure pr
             JOIN treatment_plan tp ON tp.id = pr.treatment_plan_id
             JOIN patient_profile pp ON pp.id = tp.patient_id
            WHERE pr.id = NEW.related_entity_id) <> NEW.recipient_id;
END;

-- Someone who has left cannot be paged to the floor or added to a staff
-- announcement. They may still be a patient here, so this restricts only the
-- staff-facing types.
CREATE TRIGGER trg_notif_not_to_departed BEFORE INSERT ON notification
WHEN NEW.recipient_id IS NOT NULL AND NEW.type IN ('Page','Announcement')
BEGIN
    SELECT RAISE(ABORT, 'that staff member has left the clinic')
    WHERE (SELECT employment_status FROM staff_profile WHERE user_id = NEW.recipient_id)
          IN ('Departed','OnLeave');
END;


-- =============================================================================
-- VIEWS
-- =============================================================================

-- What each person actually sees: their own messages, plus every broadcast that
-- reaches them. This is the query the inbox is built from, and it is the reason
-- recipient_role exists rather than one row per recipient.
--
-- A broadcast is delivered BY PROFILE, not by role — the rule module 1 states in
-- its own header, and the one this view got wrong first time by joining
-- n.recipient_role = u.role. Two things were broken by that:
--   · a DEPARTED doctor and one ON LEAVE both received the staff announcement
--     about contract rates, though neither can open the staff portal at all;
--   · the clinic-closed notice to Patients missed the two doctors who are
--     themselves patients here, and instead reached two provisional people who
--     booked online, never arrived, and have no patient record.
-- Staff broadcasts therefore go to staff who can actually open the portal, and
-- patient broadcasts to everyone under care, whatever their role says.
CREATE VIEW v_inbox AS
-- addressed to one person
SELECT u.id AS user_id, u.full_name AS reader, n.id AS notification_id,
       n.type, n.title, n.body, 'direct' AS addressed,
       COALESCE(s.full_name, 'system') AS sender,
       n.related_entity_type, n.related_entity_id, n.is_read, n.sent_at
FROM notification n
JOIN app_user u      ON u.id = n.recipient_id
LEFT JOIN app_user s ON s.id = n.sender_id

UNION ALL

-- broadcast to a staff role: only to staff who can open the staff portal
SELECT u.id, u.full_name, n.id, n.type, n.title, n.body, 'broadcast',
       COALESCE(s.full_name, 'system'),
       n.related_entity_type, n.related_entity_id, n.is_read, n.sent_at
FROM notification n
JOIN app_user u       ON u.role = n.recipient_role
JOIN staff_profile sp ON sp.user_id = u.id
LEFT JOIN app_user s  ON s.id = n.sender_id
WHERE n.recipient_role IS NOT NULL
  AND n.recipient_role <> 'Patient'
  AND sp.employment_status IN ('Intern','Active')

UNION ALL

-- broadcast to patients: everyone with a care relationship, staff included
SELECT u.id, u.full_name, n.id, n.type, n.title, n.body, 'broadcast',
       COALESCE(s.full_name, 'system'),
       n.related_entity_type, n.related_entity_id, n.is_read, n.sent_at
FROM notification n
JOIN patient_profile pp ON n.recipient_role = 'Patient'
JOIN app_user u         ON u.id = pp.user_id
LEFT JOIN app_user s    ON s.id = n.sender_id

ORDER BY sent_at DESC;

CREATE VIEW v_unread_count AS
SELECT user_id, reader, COUNT(*) AS unread
FROM v_inbox WHERE is_read = 0
GROUP BY user_id, reader
ORDER BY unread DESC;

-- The polymorphic pointer resolved to something a human can read. This is what
-- the trigger above buys: every link goes somewhere, so the label is never blank.
CREATE VIEW v_notification_context AS
SELECT n.id, n.type, n.title,
       COALESCE(r.full_name, 'all ' || n.recipient_role || 's') AS to_whom,
       n.related_entity_type AS about,
       CASE n.related_entity_type
           WHEN 'Appointment'   THEN (SELECT 'appointment ' || a.scheduled_at || ' (' || a.status || ')'
                                        FROM appointment a WHERE a.id = n.related_entity_id)
           WHEN 'TreatmentPlan' THEN (SELECT 'plan: ' || tp.title FROM treatment_plan tp WHERE tp.id = n.related_entity_id)
           WHEN 'TreatmentProcedure' THEN (SELECT sc.name FROM treatment_procedure pr
                                             JOIN service_category sc ON sc.id = pr.service_category_id
                                            WHERE pr.id = n.related_entity_id)
           WHEN 'Invoice'       THEN (SELECT 'invoice ' || i.status || ', total ' || i.total
                                        FROM invoice i WHERE i.id = n.related_entity_id)
           WHEN 'TreatmentFailure' THEN (SELECT 'failure reported ' || tf.reported_at
                                           FROM treatment_failure tf WHERE tf.id = n.related_entity_id)
           WHEN 'InventoryItem' THEN (SELECT it.name || ', ' || it.quantity_on_hand || ' ' || it.unit || ' on hand'
                                        FROM inventory_item it WHERE it.id = n.related_entity_id)
           WHEN 'Equipment'     THEN (SELECT e.name || ' (' || e.status || ')' FROM equipment e WHERE e.id = n.related_entity_id)
           WHEN 'PayrollRecord' THEN (SELECT 'payslip ' || p.period_start || ' to ' || p.period_end
                                        FROM payroll_record p WHERE p.id = n.related_entity_id)
       END AS context,
       n.is_read, n.sent_at
FROM notification n
LEFT JOIN app_user r ON r.id = n.recipient_id
ORDER BY n.sent_at DESC;

-- The two chases that wait on the delivery system, surfaced from the data that
-- already exists rather than from a stored queue.
CREATE VIEW v_pending_chases AS
SELECT 'NoShow reschedule' AS chase, a.id AS about, u.full_name AS person, u.phone,
       a.scheduled_at AS dated
FROM appointment a JOIN app_user u ON u.id = a.person_id
WHERE a.status = 'NoShow'
  AND NOT EXISTS (SELECT 1 FROM notification n
                   WHERE n.related_entity_type = 'Appointment' AND n.related_entity_id = a.id)
UNION ALL
SELECT 'Balance outstanding', i.id, u.full_name, u.phone, i.issued_at
FROM invoice i
JOIN patient_profile pp ON pp.id = i.patient_id
JOIN app_user u ON u.id = pp.user_id
WHERE i.status = 'PartiallyPaid'
  AND NOT EXISTS (SELECT 1 FROM notification n
                   WHERE n.related_entity_type = 'Invoice' AND n.related_entity_id = i.id)
ORDER BY dated;
