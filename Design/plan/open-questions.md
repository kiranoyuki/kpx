# KPX — Open Questions

Decisions that cannot be guessed. Corrections in this system are new rows, never edits
(rules 11, 12, 15, 43, 49, 57, 70, 73), so a wrong assumption is expensive to unwind.

Each answer becomes a worked example in the relevant `Design/workflows/*.md` file.

---

## Blocking Phase F — Billing

**1. VAT rate per service type.**
§19 records a rate per `service_category` and leaves the figures open. Vietnamese VAT does
not treat medical treatment and cosmetic work alike. Which services carry which rate?

**2. Rounding policy — confirm.**
The design assumes: allocate the invoice discount pro-rata by line value, round **down** to
whole đồng, put the remainder on the **last** line, so the shares sum exactly to the invoice
discount. Correct?

**3. Voucher plus approved discount proposal.**
§18 currently forbids stacking — a patient may use a voucher code **or** an approved
`DiscountProposal`, never both. Confirm, or state the precedence.

## Blocking Phase P — Patient app

**6. Deployment origin.**
One origin behind a reverse proxy (both apps proxy `/api` to the single API process), or
genuinely separate domains calling the API cross-origin? Patient auth follows from this — a
first-party cookie in the first case, a bearer token plus a CORS allowlist and CSRF thinking
in the second. Both UIs build against a relative `/api` base either way, so this is not
urgent for Phase P, but it **must** be answered before Phase J designs patient auth.

**7. Abuse control on `POST /api/public/booking-requests`.**
The only unauthenticated write in the system. Rate limiting alone, or a phone OTP before a
request is accepted at all? An unverified endpoint means reception's queue is spammable by
anyone who finds the URL.

**8. Phone dedup at request time.**
A request whose phone matches an existing `app_user` — link `person_id` automatically, or
show reception the match and let them decide? `idx_app_user_phone`
(`db/modules/0101_people_access_schema.sql`) is commented "dedup at booking", so the index
exists for this; the policy does not. Automatic linking on a phone number alone will
eventually attach one person's request to another person's record.

**9. Do public service listings show prices?**
A business decision, and it decides whether `GET /api/public/services` reads `price_list` at
all or only `service_category`.

## Blocking Phase H — Payroll

**4. Monthly wage pro-rating.**
§30 leaves this open. When a monthly rate changes mid-period — an intern promoted on the
15th — is the split by calendar days or working days? Hourly staff need no rule.

**5. Commission percentages.**
Per role and per service category, plus: do interns earn commission at all? §4 hints they
may not.

---

## Answered

*(none yet — move items here with the date and who confirmed)*
