# Kasa 2.0: canvas against the code

Compared on 29 Sep 2026: the Claude Design canvas
(<https://claude.ai/artifact/BidurQpqHmR9jXBWdkcs8t>, version 1790652126-dfd9)
against the uncommitted redesign in the working copy. That work analyzes
clean and all 62 app tests pass.

## Summary

The redesign has done the **system layer**:
- tokens and colours
- Geist bundled
- flat widgets with hairline borders
- the role-based tab bars (landlord 5, tenant 4, caretaker 4)
- the Needs attention list
- the caretaker Readings tab

It has **not rebuilt the screens inside the tabs.** Almost every screen still
has its old structure, restyled. The biggest recurring gaps are:

1. **No pinned action bar.** The canvas puts one primary action above the tab
   bar on every screen ("Record payment", "Add tenant", "Pay KES 25,840 with
   M-Pesa"). The app puts actions in headers, menus or inside cards.
2. **Sheets instead of screens.** Bill detail is a draggable bottom sheet; the
   canvas makes it a full screen with its own back button and action bar.
3. **Old header treatment.** Titles like "Invoices" and KPI tiles
   (TOTAL / OCCUPIED / VACANT) where the canvas has a plain app bar and one
   summary line.

## Screen by screen

✅ matches · ◐ partly · ❌ missing

### Landlord

**1 · Home** (`dashboard_screen.dart`)
- ✅ Needs attention list
- ◐ Money card. The canvas has "Collected · September", 85%, KES 214,400
  **of KES 252,000 expected**, a progress bar, then Arrears and Occupancy
  side by side. The code has no "expected" figure and no arrears total.
  **Needs backend:** expected and arrears for the month in `/dashboard/`.
- ❌ App bar: "**K**asa" wordmark and an avatar button to Profile.
- ❌ Tax and Reports tiles are on Home. The canvas moves them to Money.

**2a · Properties** (`properties_screen.dart`)
- ❌ Each property card should show: occupied x/y, **% collected with a bar**,
  **arrears**, and chips (2 overdue · 1 notice · 1 vacant).
  **Needs backend:** per-property collected, arrears and counts.
- ❌ "Add property" pinned in the action bar (today it's a header button).

**2b · Property** (`property_detail_screen.dart`)
- ❌ Units as a **3-column grid** of tiles (number, tenant, status chip).
  Today they're a list of cards.
- ❌ Filters: All / Arrears / Vacant / Notice, with counts.
- ❌ Replace the KPI tiles with one line: "Kilimani, Nairobi · 5/6 occupied".
- ◐ Meter readings and Renumber exist as full-width ghost buttons. The
  canvas has two side-by-side tiles, and the readings tile shows
  "4 missing".
- ❌ "Add tenant" pinned in the action bar.

**3 · Unit** (`unit_detail_screen.dart`)
- ✅ Notice banner (restyle as the canvas's info notice)
- ❌ Tenant card with a **call button**, plus Rent / **Deposit held** /
  Balance with a chip.
- ❌ Repairs section on the unit.
- ❌ "Record payment" pinned.

**4 · Money** (`invoices_screen.dart`)
- ❌ Title "Money" with a month picker (today: "Invoices").
- ❌ Reports and Tax statement tiles at the top (today on Home and More).
- ◐ Payments to assign. The canvas has an inline section with an Assign
  button per row; today it's a banner that opens another screen.
- ◐ Bills list. The canvas row has a unit-number avatar, name, where/due,
  and balance with a chip. It also has an "outstanding" total and
  All / Overdue / Due / Paid filters with counts.
- ❌ "Record payment" pinned.

**5 · Bill detail** (bottom sheet in `invoices_screen.dart`)
- ❌ Full screen, titled "September bill", with a download button.
- ◐ Big balance with its status chip, then an items card:
  Total / Paid / Balance.
- ◐ Payments list, then an eTIMS card with a copy button.
- ❌ Action bar: SMS reminder icon button plus "Record cash payment".

**Not yet compared in detail:**
- 6 Add tenant
- 7 Meter readings
- 8 Tax statement
- L9 Repairs
- L10 More
- The sheets board (record cash with an error, assign payment, confirm
  notice)

Expect the same pattern on these.

### Tenant

**9 · Home**
- ◐ An amount card with a **breakdown line** ("Rent 25,000 · Water 640 ·
  Garbage 200") and a "Due 5 Oct" chip.
- ❌ "Or pay by Paybill": Paybill and Account rows, each with a
  **Copy → Copied** button.
- ❌ "September paid · receipt ready" row linking to Pay.
- ◐ Pay button pinned, 56 tall.
- ❌ **"Check your phone" sheet** after tapping Pay: waiting state and
  "Pay from a different number". The pay-states board covers not
  completed, still waiting and received.

**Not yet compared in detail:**
- 10 Payments
- 11a Report a repair
- 11b Give notice
- 11c My repairs
- T5 Me

### Caretaker

**C1 · Home** (shares `dashboard_screen.dart`)
- ❌ "Today" heading with date and property.
- ❌ Three count tiles: Readings left · Open repairs · Vacant unit.
- ❌ "To do" list: read meters, repairs, move-out inspections, arrivals.
  **Needs backend:** a caretaker summary (readings left this month, open
  repairs, upcoming moves).

**Not yet compared in detail:**
- C2 Units (who lives where, a call button, no money)
- C3 Readings
- C4 Repairs

### Shared

**12a · Sign in** (`login_screen.dart`)
- ❌ No card.
- ❌ "**K**asa" wordmark, "Sign in", and a helper line.
- ❌ Labels above the fields.
- ❌ **+254 always visible**. Today Flutter only shows it once the field is
  tapped.
- ❌ Show/Hide as a text button.
- ❌ "Sign in" pinned at the bottom, with the fingerprint note.
- ❌ "Keep me signed in" is not in the design. Decide whether to keep it.

**Not yet compared in detail:**
- 12b Unlock
- 13a/b the empty / loading / error states
- The 360dp and Swahili check

## Backend needed by the design

The canvas shows figures the API doesn't provide yet:

| Figure | Screen |
|---|---|
| Expected this month, arrears total | Landlord Home |
| Per property: % collected, arrears, overdue / notice / vacant counts | Properties |
| Per unit: status for the grid (paid / arrears / vacant / notice) | Property |
| Caretaker summary: readings left, open repairs, upcoming moves | Caretaker Home |
| Outstanding total for the month | Money |

## Suggested order

1. **Commit the redesign as it stands.** It's green, and it's too much work
   to leave uncommitted.
2. **Add the shared pieces the canvas uses everywhere:**
   - an action-bar widget pinned above the tabs
   - an app bar with the wordmark and avatar
   - the unit tile
   - a list-row pattern
   - the info/warn notice

   Each screen after that is mostly arrangement.
3. **Add the backend figures** from the table above.
4. **Rebuild screens in order of use:** Landlord Home → Money → Bill →
   Property → Unit → Tenant Home and the pay flow → Caretaker Home → Sign in
   → the rest.
5. **Walk each one on the phone** against its board.
