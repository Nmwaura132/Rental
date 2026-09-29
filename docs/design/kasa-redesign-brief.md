# Kasa redesign brief

For Claude Design (claude.ai), or the `design` skill in Claude Code, which
opens the same canvas. Paste the prompt below as-is. The sections after it
are background for whoever reviews the result.

---

## The prompt

```
Design a mobile app redesign for Kasa, a rent management app for Kenya.
Deliver phone screens at 390×844, in light and dark, as one canvas.

WHO USES IT
Three roles share one app:
- Landlord (primary, pays for it): 1–5 buildings, 10–60 units. Checks who has
  paid, chases arrears, records cash, reads the tax figure once a month.
  Often 40+, not a "power user", uses a mid-range Android phone outdoors.
- Caretaker: works for the landlord on site. Reads water meters, logs
  repairs, sees who lives where. Never sees money totals.
- Tenant: sees what they owe, pays by M-Pesa, reports repairs, gives notice.
  Should be able to pay rent in under 20 seconds from opening the app.

THE LOOK
Clean, premium SaaS — the calm confidence of Linear, Stripe Dashboard, Mercury
and Revolut Business, adapted to a phone. Specifically:
- Flat surfaces, hairline 1px borders, soft low shadows used sparingly.
  No neo-brutalist hard offset shadows, no thick outlines (the current app
  has both; this is the main thing to leave behind).
- Corner radius 10–14 on cards, fully rounded only on chips and avatars.
- One accent colour, used for actions and the current tab only. Status
  colours (paid / due / overdue / vacant) are muted, never loud, and always
  paired with a word, not colour alone.
- Numbers are the hero: money in a tabular figure, large and calm. KES
  amounts are formatted "KES 25,200".
- Typeface: one clean grotesk for everything (e.g. Inter or Geist), with a
  tabular variant for money. Space Grotesk is the current display face and
  may be kept only for the wordmark.
- Keep the brand: the "Kasa" wordmark with a coral K. Coral (#FF7A66) can
  stay as the accent, or propose a better one and say why.
- Generous spacing, no dead space. No gradient hero blocks, no glassmorphism,
  no eyebrow labels above every heading, no emoji.

NAVIGATION (the main usability problem to solve)
Today: a floating pill tab bar — Home / Props / Tenants / Bills / Fix — and
several important screens (tax statement, reports, meter readings,
"payments to assign", notices) are buried inside other screens or only
reachable from one button. Propose a clearer structure. Suggested starting
point, change it if you have a better one:
- Landlord tabs: Home · Properties · Money · Maintenance · More
  - Money merges Bills, payments to assign, reports and the tax statement.
  - More holds tenants directory, caretakers, profile, settings.
- Caretaker tabs: Home · Units · Readings · Maintenance
- Tenant tabs: Home · Pay · Maintenance · Me
- One primary action per screen, in the same place every time.
- Anything that needs the landlord's attention (overdue rent, a payment to
  assign, a notice to vacate, missing meter readings) surfaces on Home as a
  short "needs attention" list, not scattered banners.

SCREENS TO DESIGN
Landlord
 1. Home — money collected this month vs expected, arrears total, "needs
    attention" list, occupancy (e.g. 9/10 occupied).
 2. Properties list, and one property: units as a compact grid/list with
    status (occupied / vacant / notice / arrears), unit numbers like G1, 1A.
 3. Unit detail — tenant, rent, deposit, notice banner if any, payment
    history, repairs.
 4. Money — this month's bills, filter by paid / due / overdue, each row:
    tenant, unit, balance, due date. Payments-to-assign as a section.
 5. Bill detail — itemised (Rent 25,000 + Water 640 + Garbage 200), payments
    against it, record cash payment, eTIMS receipt number.
 6. Add tenant — one form: person, ID photos, KRA PIN, then move-in date and
    deposit paid; shows the first bill total before submitting.
 7. Meter readings — walk-the-building list: unit, last reading, input,
    live usage and cost; save all.
 8. Tax statement (KRA monthly rental income) — tax due, rent received,
    rent roll, warnings (tenants without KRA PIN, payments without eTIMS
    receipt).
Tenant
 9. Home — amount due, due date (the 5th), big "Pay with M-Pesa", how to pay
    by paybill (Paybill 899790, Account 623943#G1) with a copy button.
10. Payment history and receipts.
11. Report a repair (photo optional), and give notice to move out.
Shared
12. Sign in — phone number (+254) and password, and fingerprint unlock.
13. Empty, loading (skeleton), and error states for Home and Money.

CONSTRAINTS
- Built in Flutter (Material 3). Everything must be buildable with standard
  widgets; no web-only effects.
- Touch targets at least 48dp. Body text at least 14. Contrast WCAG AA in
  both themes — used outdoors in direct sun.
- Must work on a 360dp-wide Android phone as well as 390.
- Motion: subtle, 150–250ms, opacity/translate only; respect reduced motion.
- English UI; leave room for Swahili strings roughly 30% longer.

DELIVERABLES
- The screens above, light and dark.
- A one-page style sheet: colour tokens (with dark values), type scale,
  spacing scale, radii, elevation, status colours, and the tab bar, buttons,
  inputs, list rows, cards, chips, and bottom sheets as components.
- A navigation map showing each role's tabs and where every screen lives.
```

---

## Background for the reviewer

**Current state (as of 28 Sep 2026).** Neo-brutalist: 2px dark outlines,
4px hard offset shadows, pill tab bar, Space Grotesk headings, Inter body,
JetBrains Mono for codes. Tokens live in
`mobile/lib/core/theme/kasa_tokens.dart` and the shared widgets in
`mobile/lib/core/widgets/kasa_primitives.dart` (KasaCard, KasaButton,
KasaChip). Because nearly every screen builds on those three widgets, a new
look can mostly be applied by changing them and the tokens, then fixing the
screens that hard-code their own styling.

**Known usability problems the redesign should fix.**
- Tax statement and reports are reachable only from one button each.
- Meter readings and renumbering are buttons inside a property.
- "Payments to assign" is a banner that only shows on the Bills tab.
- Dashboard summary card has dead space; the "CLOSED" chip clips; the
  property screen has no back button while loading.
- The Bills tab could not be refreshed when empty (fixed, but a sign the
  screen was designed around the full state only).

**Things that must survive the redesign.**
- The pay instructions exactly as the server sends them
  (`mpesa_paybill`, `pay_account` on each invoice).
- Hardware Back returning to Home from any tab root (see `router.dart`).
- Biometric unlock screen and its 60-day re-entry rule.
- Role gating: tenants never see Properties, Tenants, Reports or Tax.

**How to run it.** Either paste the prompt into Claude Design on claude.ai,
or ask Claude Code to use the `design` skill with this file; that publishes
an editable canvas you can tweak by hand before any code changes.
