"""A building's statement: one row per house per month, and the same as Excel.

WHY rows come from bills and not payments: a bill is what a month cost each
house, and its line items say how much of that was rent, water and service
charge. A payment only knows the bill it cleared, so what it paid towards each
item is worked out here (see _paid_by_item).

WHY deposits are added on: a deposit handed over on move-in was marked paid on
the tenancy and never billed, so no bill carries it. It is shown on the
tenant's first bill, beside (not inside) what the bill was paid.
"""
from datetime import date
from decimal import Decimal
from io import BytesIO

from .models import Invoice, Payment

ZERO = Decimal("0")
_METHODS = {
    Payment.Method.MPESA: "M-Pesa",
    Payment.Method.CASH: "Cash",
    Payment.Method.BANK: "Bank",
    Payment.Method.AIRTEL: "Airtel Money",
    Payment.Method.CARD: "Card",
    Payment.Method.DEPOSIT: "From deposit",
}


def statement(prop) -> dict:
    """Every month that has a bill for this building, oldest first, each with
    its rows (one per bill, by house) and totals; and every tenant's deposit."""
    bills = list(
        Invoice.objects.filter(tenancy__unit__property=prop)
        .exclude(status=Invoice.Status.CANCELLED)
        .select_related("tenancy__unit", "tenancy__tenant")
        .prefetch_related("line_items", "payments__carried_from")
        .order_by("period_start", "tenancy__unit__unit_number")
    )
    billed_deposit = {b.tenancy_id for b in bills for li in b.line_items.all() if li.charge_type == "deposit"}
    first_bill = {}
    for bill in bills:
        first_bill.setdefault(bill.tenancy_id, bill.pk)

    months: dict[date, list[dict]] = {}
    for bill in bills:
        tenancy = bill.tenancy
        on_entry = (
            tenancy.deposit_amount
            if tenancy.deposit_paid and first_bill[tenancy.pk] == bill.pk and tenancy.pk not in billed_deposit
            else ZERO
        )
        months.setdefault(bill.period_start.replace(day=1), []).append(_row(bill, on_entry))
    return {
        "months": [
            {"month": month.strftime("%Y-%m"), "label": f"{month:%B %Y}", "rows": rows, "totals": _totals(rows)}
            for month, rows in months.items()
        ],
        "deposits": _deposits(prop),
    }


def _deposits(prop) -> list[dict]:
    from apps.tenants.models import DepositSettlement, Tenancy

    rows = []
    for tenancy in (Tenancy.objects.filter(unit__property=prop)
                    .select_related("unit", "tenant").order_by("unit__unit_number", "start_date")):
        try:
            settled = tenancy.deposit_settlement
        except DepositSettlement.DoesNotExist:
            settled = None
        if settled is None:
            status = "Held" if tenancy.deposit_paid else "Not paid"
        elif settled.forfeited:
            status = "Forfeited"
        elif settled.refunded_at:
            status = f"Refunded {settled.refund_due:,.0f}"
        else:
            status = f"Settled, {settled.refund_due:,.0f} to refund"
        rows.append({
            "unit": tenancy.unit.unit_number,
            "tenant": tenancy.tenant.get_full_name(),
            "moved_in": tenancy.start_date.isoformat() if tenancy.start_date else None,
            "amount": tenancy.deposit_amount,
            "status": status,
            "held": tenancy.deposit_amount if tenancy.deposit_paid and settled is None else ZERO,
        })
    return rows


def _row(bill, deposit_on_entry=ZERO) -> dict:
    items = list(bill.line_items.all())
    paid = _paid_by_item(bill, items)
    water = [li for li in items if li.charge_type == "water"]
    reading = water[0] if len(water) == 1 and water[0].current_reading is not None else None

    def billed(kind):
        return sum((li.amount for li in items if _kind(li) == kind), ZERO)

    def paid_for(kind):
        return sum((paid[li.pk] for li in items if _kind(li) == kind), ZERO)

    return {
        "unit": bill.tenancy.unit.unit_number,
        "tenant": bill.tenancy.tenant.get_full_name(),
        "invoice": bill.invoice_number,
        "rent_billed": billed("rent"),
        "rent_paid": paid_for("rent"),
        "water_previous": reading.previous_reading if reading else None,
        "water_current": reading.current_reading if reading else None,
        "water_read_on": reading.current_read_on.isoformat() if reading and reading.current_read_on else None,
        "water_units": sum((li.units_consumed or ZERO for li in water), ZERO),
        "water_price": water[0].unit_price if water else None,
        "water_billed": billed("water"),
        "water_paid": paid_for("water"),
        "service_billed": billed("service"),
        "service_paid": paid_for("service"),
        "other_billed": billed("other"),
        "other_paid": paid_for("other"),
        "deposit_paid": paid_for("deposit") + deposit_on_entry,
        "billed": bill.amount_due,
        "paid": bill.amount_paid,
        "balance": bill.balance,
        "received": bill.amount_paid + deposit_on_entry,
        "paid_via": _paid_via(bill),
    }


def _kind(item) -> str:
    return item.charge_type if item.charge_type in ("rent", "water", "service", "deposit") else "other"


def _paid_by_item(bill, items) -> dict:
    """What the bill's payments covered of each item.

    WHY rent first: a part-paid bill is counted against rent before the
    extras, the same order deposits are settled in when a bill is paid
    (apply_confirmed_payment). Everything else goes in the order it was billed.
    """
    left = bill.amount_paid or ZERO
    paid = {}
    for item in sorted(items, key=lambda li: li.charge_type != "rent"):
        paid[item.pk] = min(left, item.amount)
        left -= paid[item.pk]
    return paid


def _paid_via(bill) -> str:
    seen = []
    for payment in bill.payments.all():
        if payment.status != Payment.Status.CONFIRMED:
            continue
        code = payment.mpesa_receipt_number or payment.bank_reference or (
            payment.carried_from.mpesa_receipt_number if payment.carried_from_id else None)
        label = f"{_METHODS.get(payment.method, payment.method)} {code}" if code else _METHODS.get(payment.method, payment.method)
        if label not in seen:
            seen.append(label)
    return ", ".join(seen)


_SUMMED = ("rent_paid", "water_units", "water_billed", "water_paid", "service_paid", "other_paid",
           "deposit_paid", "billed", "paid", "balance", "received")


def _totals(rows) -> dict:
    return {key: sum((row[key] for row in rows), ZERO) for key in _SUMMED}


# ── Excel ────────────────────────────────────────────────────────────────────

_COLUMNS = [
    ("Month", None, 14),
    ("House", "unit", 8),
    ("Tenant", "tenant", 24),
    ("Rent paid", "rent_paid", 12),
    ("Previous reading", "water_previous", 10),
    ("Current reading", "water_current", 10),
    ("Water units", "water_units", 9),
    ("Price per unit", "water_price", 9),
    ("Water charge", "water_billed", 11),
    ("Water paid", "water_paid", 11),
    ("Service charge paid", "service_paid", 11),
    ("Other paid", "other_paid", 10),
    ("Deposit paid", "deposit_paid", 11),
    ("Bill total", "billed", 12),
    ("Bill paid", "paid", 12),
    ("Balance", "balance", 11),
    ("Received (with deposit)", "received", 13),
    ("Paid via", "paid_via", 26),
]


def statement_xlsx(prop, months: list[dict], deposits: list[dict]) -> bytes:
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    from openpyxl.utils import get_column_letter

    book = Workbook()
    sheet = book.active
    sheet.title = "Statement"
    bold = Font(bold=True)
    rule = Border(top=Side(style="thin"))
    shade = PatternFill("solid", fgColor="F2F2F2")
    money = "#,##0;-#,##0;-"

    span = f"{months[0]['label']} to {months[-1]['label']}" if months else "no bills yet"
    sheet.append([f"{prop.name}: statement, {span}"])
    sheet["A1"].font = Font(bold=True, size=13)
    sheet.append([])
    sheet.append([title for title, _, _ in _COLUMNS])
    for cell in sheet[3]:
        cell.font = bold
        cell.fill = shade
        cell.alignment = Alignment(wrap_text=True, vertical="bottom")

    def add(values, *, strong=False):
        sheet.append(values)
        for cell in sheet[sheet.max_row]:
            if strong:
                cell.font = bold
                cell.border = rule
            if isinstance(cell.value, Decimal):
                cell.number_format = money

    for month in months:
        for row in month["rows"]:
            add([month["label"]] + [row[key] for _, key, _ in _COLUMNS[1:]])
        add([f"{month['label']} total", "", ""] + [
            month["totals"].get(key, "") if key in _SUMMED else "" for _, key, _ in _COLUMNS[3:]
        ], strong=True)
        sheet.append([])

    grand = {key: sum((m["totals"][key] for m in months), ZERO) for key in _SUMMED}
    add(["All months", "", ""] + [grand[key] if key in _SUMMED else "" for _, key, _ in _COLUMNS[3:]], strong=True)

    for index, (_, _, width) in enumerate(_COLUMNS, start=1):
        sheet.column_dimensions[get_column_letter(index)].width = width
    sheet.append([])
    sheet.append(["A part-paid bill is counted against rent first, then the other charges."])
    sheet.cell(sheet.max_row, 1).font = Font(italic=True, color="666666")
    sheet.append(["A deposit paid on move-in is shown on the tenant's first bill, outside the bill's own total."])
    sheet.cell(sheet.max_row, 1).font = Font(italic=True, color="666666")

    held = book.create_sheet("Deposits")
    held.append([f"{prop.name}: deposits"])
    held["A1"].font = Font(bold=True, size=13)
    held.append([])
    held.append(["House", "Tenant", "Moved in", "Deposit", "Status", "Held now"])
    for cell in held[3]:
        cell.font = bold
        cell.fill = shade
    for row in deposits:
        moved_in = date.fromisoformat(row["moved_in"]) if row["moved_in"] else None
        held.append([row["unit"], row["tenant"], moved_in, row["amount"], row["status"], row["held"]])
        held.cell(held.max_row, 3).number_format = "d mmm yyyy"
        for column in (4, 6):
            held.cell(held.max_row, column).number_format = money
    held.append(["Total held", "", "", "", "", sum((r["held"] for r in deposits), ZERO)])
    for cell in held[held.max_row]:
        cell.font = bold
        cell.border = rule
    held.cell(held.max_row, 6).number_format = money
    for letter, width in zip("ABCDEF", (8, 24, 13, 12, 24, 12)):
        held.column_dimensions[letter].width = width

    buffer = BytesIO()
    book.save(buffer)
    return buffer.getvalue()


# ── PDF ──────────────────────────────────────────────────────────────────────

def _k(value) -> str:
    """25000 -> "25,000"; nothing -> a dash, so empty cells read as empty."""
    if value is None or value == "":
        return "-"
    return f"{value:,.0f}" if value == value.to_integral_value() else f"{value:,.2f}"


def statement_pdf(prop, months: list[dict], deposits: list[dict]) -> bytes:
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.units import cm
    from reportlab.platypus import KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

    ink = colors.HexColor("#1c1c1c")
    muted = colors.HexColor("#6b6b6b")
    rule = colors.HexColor("#d9d9d9")
    band = colors.HexColor("#f4f4f4")
    red = colors.HexColor("#b3261e")

    # WHY these sizes: the statement is read by older landlords, often printed,
    # so nothing is set below 9pt.
    title = ParagraphStyle("t", fontName="Helvetica-Bold", fontSize=18, leading=22, textColor=ink)
    sub = ParagraphStyle("s", fontName="Helvetica", fontSize=10.5, leading=14, textColor=muted)
    heading = ParagraphStyle("h", fontName="Helvetica-Bold", fontSize=13, leading=16, textColor=ink,
                             spaceBefore=16, spaceAfter=6)
    cell = ParagraphStyle("c", fontName="Helvetica", fontSize=9.5, leading=12, textColor=ink)
    note = ParagraphStyle("n", fontName="Helvetica-Oblique", fontSize=9, leading=12, textColor=muted)

    def grid(rows, widths, *, numeric_from, text_columns=(), total_rows=(), extra=()):
        table = Table(rows, colWidths=[w * cm for w in widths], repeatRows=1, hAlign="LEFT")
        style = [
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
            ("FONTSIZE", (0, 0), (-1, -1), 9.5),
            ("TEXTCOLOR", (0, 0), (-1, -1), ink),
            ("TEXTCOLOR", (0, 0), (-1, 0), muted),
            ("LINEBELOW", (0, 0), (-1, 0), 0.8, ink),
            ("LINEBELOW", (0, 1), (-1, -1), 0.3, rule),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ("LEFTPADDING", (0, 0), (-1, -1), 3),
            ("RIGHTPADDING", (0, 0), (-1, -1), 3),
            ("ALIGN", (numeric_from, 0), (-1, -1), "RIGHT"),
        ]
        style += [("ALIGN", (c, 0), (c, -1), "LEFT") for c in text_columns]
        style += list(extra)
        for r in total_rows:
            style += [("FONTNAME", (0, r), (-1, r), "Helvetica-Bold"), ("BACKGROUND", (0, r), (-1, r), band),
                      ("LINEABOVE", (0, r), (-1, r), 0.8, ink)]
        table.setStyle(TableStyle(style))
        return table

    grand = {key: sum((m["totals"][key] for m in months), ZERO) for key in _SUMMED}
    held_now = sum((d["held"] for d in deposits), ZERO)
    span = f"{months[0]['label']} to {months[-1]['label']}" if months else "No bills yet"
    today = date.today()
    story = [
        Paragraph(prop.name, title),
        Paragraph(f"Statement &middot; {span} &middot; prepared {today.day} {today:%b %Y}", sub),
        Spacer(1, 0.5 * cm),
    ]

    summary = [
        ["Billed", _k(grand["billed"]), "Rent paid", _k(grand["rent_paid"]),
         "Deposits received", _k(grand["deposit_paid"])],
        ["Paid on bills", _k(grand["paid"]), "Water paid",
         f"{_k(grand['water_paid'])}  ({_k(grand['water_units'])} units)", "Total received", _k(grand["received"])],
        ["Still owed", _k(grand["balance"]), "Service charge paid", _k(grand["service_paid"]),
         "Deposits held now", _k(held_now)],
    ]
    box = Table(summary, colWidths=[w * cm for w in (3.6, 3.6, 4.2, 4.8, 4.2, 3.6)], hAlign="LEFT")
    box.setStyle(TableStyle([
        ("FONTSIZE", (0, 0), (-1, -1), 11),
        ("TEXTCOLOR", (0, 0), (-1, -1), ink),
        *[("TEXTCOLOR", (c, 0), (c, -1), muted) for c in (0, 2, 4)],
        *[("FONTNAME", (c, 0), (c, -1), "Helvetica-Bold") for c in (1, 3, 5)],
        *[("ALIGN", (c, 0), (c, -1), "RIGHT") for c in (1, 3, 5)],
        ("TEXTCOLOR", (1, 2), (1, 2), red if grand["balance"] > 0 else ink),
        ("BOX", (0, 0), (-1, -1), 0.5, rule),
        ("BACKGROUND", (0, 0), (-1, -1), band),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(box)

    head = ["House", "Tenant", "Rent", "Readings", "Units", "Rate", "Water", "Service", "Deposit",
            "Bill", "Paid", "Balance", "Paid via"]
    widths = [1.3, 3.7, 1.8, 2.3, 1.2, 1.1, 1.6, 1.6, 1.8, 1.9, 1.9, 1.7, 4.8]
    for month in months:
        rows = [head]
        for r in month["rows"]:
            readings = (f"{_k(r['water_previous'])} to {_k(r['water_current'])}"
                        if r["water_current"] is not None else "-")
            rows.append([
                r["unit"], Paragraph(r["tenant"], cell), _k(r["rent_paid"]), readings,
                _k(r["water_units"]) if r["water_units"] else "-", _k(r["water_price"]),
                _k(r["water_billed"]) if r["water_billed"] else "-", _k(r["service_paid"]), _k(r["deposit_paid"]) if r["deposit_paid"] else "-",
                _k(r["billed"]), _k(r["paid"]), _k(r["balance"]), Paragraph(r["paid_via"] or "-", cell),
            ])
        t = month["totals"]
        rows.append(["Total", "", _k(t["rent_paid"]), "", _k(t["water_units"]), "", _k(t["water_billed"]),
                     _k(t["service_paid"]), _k(t["deposit_paid"]), _k(t["billed"]), _k(t["paid"]),
                     _k(t["balance"]), ""])
        story.append(KeepTogether([
            Paragraph(month["label"], heading),
            grid(rows, widths, numeric_from=2, text_columns=(3, 12), total_rows=(len(rows) - 1,),
                 extra=[("LEFTPADDING", (3, 0), (3, -1), 12)]),
        ]))

    if deposits:
        rows = [["House", "Tenant", "Moved in", "Deposit", "Status", "Held now"]]
        for d in deposits:
            moved_in = date.fromisoformat(d["moved_in"]) if d["moved_in"] else None
            rows.append([d["unit"], Paragraph(d["tenant"], cell),
                         f"{moved_in.day} {moved_in:%b %Y}" if moved_in else "-",
                         _k(d["amount"]), d["status"], _k(d["held"])])
        rows.append(["Total held", "", "", "", "", _k(held_now)])
        story.append(KeepTogether([
            Paragraph("Deposits", heading),
            grid(rows, [1.3, 5.0, 3.0, 2.6, 5.0, 2.6], numeric_from=3, text_columns=(4,),
                 total_rows=(len(rows) - 1,)),
        ]))

    story += [
        Spacer(1, 0.5 * cm),
        Paragraph("Amounts in KES. Water is the previous month's use, billed at the rate shown. A part-paid bill "
                  "is counted against rent first. A deposit paid on moving in is shown in that month, outside "
                  "the bill.", note),
    ]

    def footer(canvas, doc):
        canvas.saveState()
        canvas.setFont("Helvetica", 7.5)
        canvas.setFillColor(muted)
        canvas.drawString(1.5 * cm, 1 * cm, f"{prop.name} statement")
        canvas.drawRightString(landscape(A4)[0] - 1.5 * cm, 1 * cm, f"Page {doc.page}")
        canvas.restoreState()

    buffer = BytesIO()
    SimpleDocTemplate(
        buffer, pagesize=landscape(A4), leftMargin=1.5 * cm, rightMargin=1.5 * cm,
        topMargin=1.5 * cm, bottomMargin=1.6 * cm, title=f"{prop.name} statement", author="Kasa",
    ).build(story, onFirstPage=footer, onLaterPages=footer)
    return buffer.getvalue()
