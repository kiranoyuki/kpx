# KPX — The scheduling model

> **A service determines what resources and duration are needed. An appointment
> reserves those resources for a time interval.**

Decided 2026-09-06 (`plan/decisions.md`). This supersedes the scheduling parts of
`entities.md` module 3, which modelled an appointment as *doctor + chair +
timestamp*.

---

## The rule that shapes everything

**A slot is not a chair, a doctor and a timestamp.**

> A slot represents the ability to fulfil a **service** during a particular time
> interval, given the providers and resources currently available.

An appointment is the durable object. A slot is an offer, computed on demand and
gone the moment it is taken.

### Why not store slots

Storing them means choosing the chair before anyone knows what the patient wants:

```
10:00  Dr A  Chair 1        ← the same half hour, five times over,
10:00  Dr A  Chair 2          four of them meaningless, because a
10:00  Dr A  Chair 3          doctor is only ever in one chair
```

Five chairs × six providers × twenty half-hours is 600 rows a day to keep in step
with schedules that change. Computing availability instead means the answer is
never stale, and the chair is chosen at the last possible moment — when the
service is known and the transaction is open.

### Why the slot id is opaque

```
✗  doctor_123_20260910_1000_chair_04
✓  slot_9a6403b0-f27d-48b7
```

An id identifies a thing; it does not describe its current state. Move the
appointment fifteen minutes, or swap Chair 3 for Chair 4, and the appointment is
still the same appointment. Encode the state in the id and it is not.

It also settles the timezone problem by removing it: the patient app sends a
`slotId` and never a date and time, so there is no client-side arithmetic to get
wrong (`conventions.md` §4).

---

## The entities

```
Clinic
├── Resource ──── ResourceType
├── Provider ──── ProviderServiceCapability
├── Service ───── ServiceResourceRequirement
├── ProviderSchedule
├── Appointment ── AppointmentResource
│                └ AppointmentReason
└── TreatmentPlan ── Appointment
```

```
              Service
                 │  defines duration and requirements
                 ↓
Provider ←── Appointment ──→ Resource
                 │
                 ↓
              Patient
                 │
                 ↓
           TreatmentPlan   (when the work spans visits)
```

### What already exists, and under what name

Most of this is in the schema already. The table below is the mapping, so no one
builds a second copy of something that is there.

| Model | Today | Change |
|---|---|---|
| Resource | `chair` | rename; an X-ray *room* is currently stored as a "chair" |
| ResourceType | `chair_type` | rename |
| Service | `service_category` | **add** `default_duration_minutes`, `booking_policy` |
| ServiceResourceRequirement | `service_category.required_chair_type_id` | **replace** — one required type becomes many *allowed* types |
| ProviderServiceCapability | — | **new** |
| ProviderSchedule | `doctor_schedule` | unchanged |
| Appointment | `appointment` | **add** `service_id`, `treatment_plan_id`; split `scheduled_at`; drop `chair_id` |
| AppointmentResource | `appointment.chair_id` | **new** — one column becomes a join table |
| AppointmentReason | — | **new** |
| TreatmentPlan | `treatment_plan` | unchanged; appointments gain a link to it |

---

## Services carry their scheduling rules

Duration and who may book are properties of the service, not of code.

| Service | Duration | Booking policy |
|---|---|---|
| Initial consultation | 30 min | `PatientBookable` |
| Cleaning | 45 min | `PatientBookable` |
| Filling | 45 min | `StaffBookable` |
| Implant consultation | 30 min | `PatientBookable` |
| Implant surgery | 90 min | `StaffOnly` |
| Follow-up | 20 min | `FollowUp` |

`booking_policy` is what stops the patient app offering an implant surgery. It is
configuration, not a branch in a handler.

### Requirements are a list of *allowed* types, not one required type

```
Initial consultation   → ConsultRoom OR RegularChair
Cleaning               → RegularChair
Implant surgery        → ImplantRoom
Implant follow-up      → RegularChair OR ConsultRoom
```

The `OR` is the point. `required_chair_type_id` forces a consultation into a
consult room even when four chairs sit empty; a list lets reception use the
capacity it has.

### Providers are qualified per service, not by role

```
              Cleaning  Consultation  Implant consult  Implant surgery
Dr Minh          yes         yes            no               no
Dr Khoa          yes         yes            yes              yes
```

Availability then asks *who can perform this*, rather than inferring it from
`role` — which cannot express that one doctor places implants and another does
not.

---

## The availability engine

```
        Service (duration, requirements, policy)
                        ↓
            providers qualified for it
                        ∩
              provider working hours
                        ∩
                 clinic open           ← see below
                        ∩
        resources of an allowed type, free
                        −
              existing appointments
                        ↓
                 available times
```

It lives in the API — `modules/scheduling/domain/availability.ts` — and nowhere
else. Neither front end decides whether a slot is free, and neither decides what
a time means.

The patient sees only times:

```
Tuesday 10 September      09:00   09:45   10:30   11:15
```

Not chairs, not which doctor is free when, unless they asked for a specific one.

### Clinic hours

This closes the gap `conventions.md` §13 has carried since the start — *booking
needs doctor free, chair free, and clinic open, and the third has no entity*.

**Clinic opening hours become a resource-free constraint in the engine**, sourced
from a small `clinic_hours` table: weekday windows plus dated exceptions, the same
shape `doctor_schedule` already uses. It is one table and it makes Tết a row
rather than a special case in code.

---

## Booking, and where the chair is decided

Availability says a time is possible because *some* suitable resource is free. It
does not pick one. The choice happens inside the booking transaction, at the last
moment, when the service is known:

```
BEGIN
  re-check: provider still free, resource of an allowed type still free
  choose a resource
  insert appointment
  insert appointment_resource
COMMIT
```

Re-checking is not optional — the offer was made before the transaction opened.
Under `conventions.md` §3 this is atomic against other requests in the process,
which is what makes the check-then-write sound.

---

## What the patient asks for, and what gets booked

These are different things, and conflating them is the mistake this separates.

```
Patient says          "I'm interested in an implant"
System books          Initial implant consultation · 30 min · consult room
                      · an implant-qualified doctor
Recorded as           appointment.service_id  = InitialImplantConsultation
                      appointment_reason      = Implant
```

Nobody books an implant surgery from a phone. They book the conversation that
decides whether there will be one. `appointment_reason` keeps *why they came*
without pretending it is *what was scheduled*.

---

## Work that spans visits

An implant is not an appointment. It is a `treatment_plan` with several:

```
TreatmentPlan  "Implant #36"  · Dr Khoa · Active
   ├── implant consultation
   ├── implant placement
   ├── 7-day follow-up
   ├── healing check
   └── crown placement
```

`treatment_plan` already exists with the right shape — patient, doctor, title,
status, dates. What is missing is `appointment.treatment_plan_id`, so a visit can
say which course of work it belongs to.

---

## First implementation: two services

Phase B1 builds **Initial consultation** and **Cleaning**, and nothing else.

Between them they exercise every hard part — patient self-booking, two different
durations, provider qualification, `OR` on resource types, resource assignment,
cancellation, and the concurrency re-check — without the treatment-case workflow
an implant needs. Everything after that is configuration rather than new code,
which is the test of whether this model is right.
