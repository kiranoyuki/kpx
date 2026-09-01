-- =============================================================================
-- KPX — MODULE 3 seed: Scheduling
--
-- 7 schedule blocks, 8 appointments. Deliberate edge cases:
--   · two appointments at the SAME time in DIFFERENT chairs — parallel capacity
--   · a Provisional person holding a future booking, self-booked (created_by NULL)
--   · a Provisional no-show that must surface in the reschedule chase
--   · one appointment InProgress, so chair occupancy has something to show
--   · a Cancelled appointment, which must release its slot
--   · a Followup carrying followed_up_by — the receptionist's KPI credit
--   · a one-off availability override (a public holiday)
-- =============================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- ------------------------------------------------------------- availability --
-- Dr Minh works mornings and afternoons Mon–Fri; Dr Quỳnh a single long day.
INSERT INTO doctor_schedule (id, doctor_id, day_of_week, date, start_time, end_time, is_available, note) VALUES
('ds-01', 'st-doc01', 1, NULL, '08:00', '12:00', 1, 'Mon morning'),
('ds-02', 'st-doc01', 1, NULL, '13:00', '17:00', 1, 'Mon afternoon'),
('ds-03', 'st-doc01', 2, NULL, '08:00', '12:00', 1, 'Tue morning'),
('ds-04', 'st-doc01', 4, NULL, '08:00', '17:00', 1, 'Thu, full day'),
('ds-05', 'st-doc04', 2, NULL, '09:00', '18:00', 1, 'Tue, full day'),
('ds-06', 'st-doc04', 3, NULL, '09:00', '18:00', 1, 'Wed, full day'),
-- a one-off override: National Day, clinic closed for Dr Minh
('ds-07', 'st-doc01', NULL, '2026-09-02', '00:00', '23:59', 0, 'National Day — not working');

-- ------------------------------------------------------------- appointments --
-- ap-01 and ap-02 are at the SAME time in DIFFERENT chairs with DIFFERENT
-- doctors: the clinic runs two chairs in parallel, and nothing should object.
INSERT INTO appointment
    (id, person_id, doctor_id, chair_id, scheduled_at, duration_minutes, type, status,
     booking_channel, assistant_id, followed_up_by, notes, created_by, created_at) VALUES
('ap-01','u-pat01','st-doc01','ch-01','2026-08-25 09:00:00',45,'Consultation','Completed','FrontDesk',NULL,      NULL,      'Routine check.',                                   'u-rec01','2026-08-20 10:05:00'),
('ap-02','u-pat02','st-doc04','ch-02','2026-08-25 09:00:00',60,'Procedure',   'Completed','Online',   'st-ast01',NULL,      'Same slot, second chair — parallel capacity.',      NULL,     '2026-08-18 21:30:00'),

-- a Provisional person who booked online and never arrived
('ap-03','u-prv02','st-doc01','ch-01','2026-08-20 10:00:00',45,'Consultation','NoShow',   'Online',   NULL,      NULL,      'Self-booked online, did not attend.',              NULL,     '2026-08-11 21:47:00'),

-- a Provisional person holding a FUTURE booking: not yet a patient, but the
-- appointment points at them perfectly well
('ap-04','u-prv01','st-doc04','ch-01','2026-09-05 16:00:00',45,'Consultation','Scheduled','Online',   NULL,      NULL,      'New patient, self-booked. Verify CCCD on arrival.',NULL,'2026-08-26 20:14:00'),

-- a follow-up the receptionist chased — her KPI credit
('ap-05','u-pat03','st-doc01','ch-03','2026-09-03 08:30:00',90,'Procedure',   'Confirmed','Phone',    'st-ast01','u-rec01', 'Booked after recall call.',                        'u-rec01','2026-08-28 09:20:00'),
('ap-06','u-pat04','st-doc04','ch-02','2026-09-02 14:00:00',30,'Followup',    'Scheduled','FrontDesk',NULL,      'u-rec01', 'Six-month recall.',                                'u-rec01','2026-08-30 11:00:00'),

-- in the chair right now, so occupancy has something to report
('ap-07','u-pat02','st-doc01','ch-01','2026-09-01 10:00:00',60,'Procedure',   'InProgress','FrontDesk','st-ast01',NULL,     'Currently being treated.',                         'u-rec01','2026-08-27 15:40:00'),

-- cancelled: must RELEASE its slot, so ch-02 is free at that time
('ap-08','u-pat03','st-doc04','ch-02','2026-08-28 11:00:00',60,'Procedure',   'Cancelled','FrontDesk',NULL,      NULL,      'Patient cancelled, work commitment.',              'u-rec01','2026-08-21 09:00:00');


COMMIT;
