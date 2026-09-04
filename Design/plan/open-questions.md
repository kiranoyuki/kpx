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
