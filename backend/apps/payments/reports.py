"""
Financial report PDF generators for the Rental Manager system.
All functions return raw bytes (PDF) ready to upload to MinIO.
Follows the same ReportLab patterns as apps/tenants/lease_pdf.py.
"""
import io
from datetime import date, timedelta
from decimal import Decimal

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (
    HRFlowable, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle,
)

_HEADER_COLOR = colors.HexColor('#1a237e')
_ROW_A = colors.HexColor('#e8eaf6')
_BORDER = colors.HexColor('#c5cae9')


def _style(base, **kwargs):
    return ParagraphStyle(base + '_r', parent=getSampleStyleSheet()[base], **kwargs)


def _hr():
    return HRFlowable(width='100%', thickness=0.5, color=_BORDER, spaceAfter=8, spaceBefore=4)


def _doc(buffer):
    return SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=2.5 * cm,
        rightMargin=2.5 * cm,
        topMargin=2 * cm,
        bottomMargin=2 * cm,
    )


def _table_style(header_cols=None):
    header_cols = header_cols or (-1,)  # tuple of (col_end,)
    return TableStyle([
        ('BACKGROUND', (0, 0), (header_cols[0], 0), _HEADER_COLOR),
        ('TEXTCOLOR', (0, 0), (header_cols[0], 0), colors.white),
        ('FONTNAME', (0, 0), (header_cols[0], 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('PADDING', (0, 0), (-1, -1), 5),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [_ROW_A, colors.white]),
        ('GRID', (0, 0), (-1, -1), 0.3, _BORDER),
    ])


def _fmt_money(amount):
    try:
        return f"KES {float(amount):,.0f}"
    except (TypeError, ValueError):
        return f"KES {amount}"


def _fmt_date(d):
    if d is None:
        return '—'
    if isinstance(d, str):
        try:
            from datetime import datetime
            d = datetime.fromisoformat(d).date()
        except ValueError:
            return d
    try:
        return d.strftime('%d %b %Y')
    except AttributeError:
        return str(d)


def _header_para(text):
    return Paragraph(text, _style('Title', fontSize=15, spaceAfter=4,
                                  textColor=_HEADER_COLOR))


def _sub_para(text):
    return Paragraph(text, _style('Normal', fontSize=9, textColor=colors.grey,
                                  alignment=TA_CENTER, spaceAfter=10))


def _section(text):
    return Paragraph(text, _style('Heading2', fontSize=10, textColor=_HEADER_COLOR,
                                  spaceBefore=10, spaceAfter=4))


# ─────────────────────────────────────────────────────────────────────────────
# Report 1: Monthly P&L
# ─────────────────────────────────────────────────────────────────────────────

def generate_monthly_pnl(prop, year: int, month: int) -> bytes:
    """Monthly rent collection P&L for a single property."""
    from apps.tenants.models import Lease
    from apps.payments.models import Invoice, Payment

    import calendar
    from django.db.models import Sum

    first_day = date(year, month, 1)
    last_day = date(year, month, calendar.monthrange(year, month)[1])
    month_label = first_day.strftime('%B %Y')

    # All active/expired leases for this property with units
    leases = Lease.objects.filter(
        unit__property=prop
    ).select_related('unit', 'tenant')

    rows = []
    total_expected = Decimal('0')
    total_collected = Decimal('0')
    method_totals: dict[str, Decimal] = {}

    for lease in leases:
        invoices = Invoice.objects.filter(
            lease=lease,
            period_start__lte=last_day,
            period_end__gte=first_day,
        )
        expected = invoices.aggregate(s=Sum('amount_due'))['s'] or Decimal('0')
        payments = Payment.objects.filter(
            invoice__lease=lease,
            status='confirmed',
            paid_at__date__gte=first_day,
            paid_at__date__lte=last_day,
        )
        collected = payments.aggregate(s=Sum('amount'))['s'] or Decimal('0')
        balance = expected - collected

        # Method breakdown
        for p in payments.values('method', 'amount'):
            m = p['method'] or 'other'
            method_totals[m] = method_totals.get(m, Decimal('0')) + (p['amount'] or Decimal('0'))

        total_expected += expected
        total_collected += collected

        rows.append([
            lease.unit.unit_number,
            lease.tenant.get_full_name(),
            _fmt_money(expected),
            _fmt_money(collected),
            _fmt_money(balance),
        ])

    collection_rate = (
        round(float(total_collected) / float(total_expected) * 100, 1)
        if total_expected else 0.0
    )
    gross_rent = float(total_collected)
    rrit = round(gross_rent * 0.075, 2)
    next_month = (first_day.replace(day=20) + timedelta(days=32)).replace(day=20)

    buffer = io.BytesIO()
    doc = _doc(buffer)
    story = []

    story.append(_header_para(f"Monthly Rent Collection Report — {month_label}"))
    story.append(_sub_para(f"Property: {prop.name}  |  Generated: {date.today().strftime('%d %b %Y')}"))
    story.append(_hr())

    story.append(_section("Rent Summary"))
    table_data = [['Unit', 'Tenant', 'Rent Due', 'Collected', 'Balance']] + rows
    table_data.append(['', 'TOTALS', _fmt_money(total_expected),
                       _fmt_money(total_collected), _fmt_money(total_expected - total_collected)])
    t = Table(table_data, colWidths=[2.5 * cm, 5 * cm, 3.5 * cm, 3.5 * cm, 3 * cm])
    ts = _table_style()
    # Bold last row (totals)
    ts.add('FONTNAME', (0, len(table_data) - 1), (-1, len(table_data) - 1), 'Helvetica-Bold')
    ts.add('BACKGROUND', (0, len(table_data) - 1), (-1, len(table_data) - 1), _ROW_A)
    t.setStyle(ts)
    story.append(t)

    story.append(Spacer(1, 0.4 * cm))
    story.append(_section("Collection Summary"))
    summary_data = [
        ['Metric', 'Value'],
        ['Total Expected', _fmt_money(total_expected)],
        ['Total Collected', _fmt_money(total_collected)],
        ['Collection Rate', f"{collection_rate}%"],
        ['Outstanding', _fmt_money(total_expected - total_collected)],
    ]
    for method, amt in method_totals.items():
        summary_data.append([f"  Collected via {method.upper()}", _fmt_money(amt)])

    st = Table(summary_data, colWidths=[8 * cm, 8 * cm])
    st.setStyle(_table_style())
    story.append(st)

    story.append(Spacer(1, 0.4 * cm))
    story.append(_section("KRA — Residential Rental Income Tax (RRIT)"))
    kra_data = [
        ['Description', 'Amount'],
        ['Gross Rental Income', _fmt_money(gross_rent)],
        ['RRIT @ 7.5%', f"KES {rrit:,.2f}"],
        ['Payment Due Date', f"20th of next month ({next_month.strftime('%d %b %Y')})"],
        ['Payment Method', 'KRA iTax → Income Tax → Rental Income'],
    ]
    kt = Table(kra_data, colWidths=[8 * cm, 8 * cm])
    kt.setStyle(_table_style())
    story.append(kt)

    doc.build(story)
    return buffer.getvalue()


# ─────────────────────────────────────────────────────────────────────────────
# Report 2: Aged Receivables
# ─────────────────────────────────────────────────────────────────────────────

def generate_aged_receivables(prop) -> bytes:
    """Outstanding invoice aging report for a property."""
    from apps.payments.models import Invoice
    from django.db.models import Sum

    today = date.today()
    outstanding = Invoice.objects.filter(
        lease__unit__property=prop,
        status__in=['pending', 'overdue', 'partially_paid'],
    ).select_related('lease__tenant', 'lease__unit')

    def bucket(days):
        if days <= 0:
            return 'Current'
        if days <= 30:
            return '1–30 days'
        if days <= 60:
            return '31–60 days'
        if days <= 90:
            return '61–90 days'
        return '90+ days'

    BUCKETS = ['Current', '1–30 days', '31–60 days', '61–90 days', '90+ days']
    bucket_totals: dict[str, Decimal] = {b: Decimal('0') for b in BUCKETS}

    rows = []
    for inv in outstanding:
        days_overdue = (today - inv.due_date).days
        bal = (inv.amount_due or Decimal('0')) - (inv.amount_paid or Decimal('0'))
        b = bucket(days_overdue)
        bucket_totals[b] += bal
        rows.append([
            inv.lease.tenant.get_full_name(),
            inv.lease.unit.unit_number,
            inv.invoice_number,
            _fmt_date(inv.due_date),
            _fmt_money(inv.amount_due),
            _fmt_money(inv.amount_paid),
            _fmt_money(bal),
            b,
        ])

    buffer = io.BytesIO()
    doc = _doc(buffer)
    story = []

    story.append(_header_para("Aged Receivables Report"))
    story.append(_sub_para(f"Property: {prop.name}  |  As of: {today.strftime('%d %b %Y')}"))
    story.append(_hr())

    story.append(_section("Outstanding Invoices"))
    table_data = [['Tenant', 'Unit', 'Invoice #', 'Due Date', 'Amount Due', 'Paid', 'Balance', 'Age']] + rows
    t = Table(table_data, colWidths=[3.5 * cm, 1.5 * cm, 3 * cm, 2.5 * cm,
                                     2.5 * cm, 2.5 * cm, 2.5 * cm, 2 * cm])
    t.setStyle(_table_style())
    story.append(t)

    story.append(Spacer(1, 0.4 * cm))
    story.append(_section("Aging Buckets Summary"))
    bucket_data = [['Bucket', 'Total Outstanding']]
    for b in BUCKETS:
        bucket_data.append([b, _fmt_money(bucket_totals[b])])
    bucket_data.append(['GRAND TOTAL', _fmt_money(sum(bucket_totals.values()))])
    bt = Table(bucket_data, colWidths=[8 * cm, 8 * cm])
    bts = _table_style()
    bts.add('FONTNAME', (0, len(bucket_data) - 1), (-1, len(bucket_data) - 1), 'Helvetica-Bold')
    bt.setStyle(bts)
    story.append(bt)

    doc.build(story)
    return buffer.getvalue()


# ─────────────────────────────────────────────────────────────────────────────
# Report 3: Tenant Ledger
# ─────────────────────────────────────────────────────────────────────────────

def generate_tenant_ledger(lease, date_from: date, date_to: date) -> bytes:
    """Chronological statement of debits (invoices) and credits (payments) for a lease."""
    from apps.payments.models import Invoice, Payment

    prop = lease.unit.property
    tenant = lease.tenant

    invoices = Invoice.objects.filter(
        lease=lease,
        due_date__range=(date_from, date_to),
    ).order_by('due_date')

    payments = Payment.objects.filter(
        invoice__lease=lease,
        paid_at__date__range=(date_from, date_to),
        status='confirmed',
    ).order_by('paid_at')

    # Build chronological ledger entries
    entries = []
    for inv in invoices:
        entries.append({
            'date': inv.due_date,
            'description': f"Invoice {inv.invoice_number}",
            'debit': inv.amount_due,
            'credit': Decimal('0'),
        })
    for pay in payments:
        entries.append({
            'date': pay.paid_at.date(),
            'description': f"Payment — {pay.method.upper()}",
            'debit': Decimal('0'),
            'credit': pay.amount,
        })
    entries.sort(key=lambda e: e['date'])

    rows = []
    balance = Decimal('0')
    for e in entries:
        balance += e['debit'] - e['credit']
        rows.append([
            _fmt_date(e['date']),
            e['description'],
            _fmt_money(e['debit']) if e['debit'] else '—',
            _fmt_money(e['credit']) if e['credit'] else '—',
            _fmt_money(balance),
        ])

    buffer = io.BytesIO()
    doc = _doc(buffer)
    story = []

    story.append(_header_para("Tenant Ledger Statement"))
    story.append(_sub_para(
        f"Tenant: {tenant.get_full_name()}  |  Unit: {lease.unit.unit_number}, {prop.name}  |  "
        f"Period: {_fmt_date(date_from)} – {_fmt_date(date_to)}"
    ))
    story.append(_hr())

    table_data = [['Date', 'Description', 'Debit', 'Credit', 'Balance']] + rows
    t = Table(table_data, colWidths=[2.5 * cm, 6 * cm, 3 * cm, 3 * cm, 3 * cm])
    t.setStyle(_table_style())
    story.append(t)

    story.append(Spacer(1, 0.3 * cm))
    closing = Paragraph(
        f"<b>Closing Balance: {_fmt_money(balance)}</b>  "
        f"({'Amount Due' if balance > 0 else 'Credit' if balance < 0 else 'Nil'})",
        _style('Normal', fontSize=10, textColor=_HEADER_COLOR),
    )
    story.append(closing)

    doc.build(story)
    return buffer.getvalue()


# ─────────────────────────────────────────────────────────────────────────────
# Report 4: Rent Roll
# ─────────────────────────────────────────────────────────────────────────────

def generate_rent_roll(prop) -> bytes:
    """Current rent roll — all units with lease and payment status."""
    from apps.properties.models import Unit
    from apps.tenants.models import Lease
    from apps.payments.models import Payment
    from django.db.models import Max

    units = Unit.objects.filter(property=prop).order_by('unit_number')

    rows = []
    total_expected = Decimal('0')
    total_arrears = Decimal('0')
    occupied = 0

    for unit in units:
        lease = Lease.objects.filter(
            unit=unit, status='active'
        ).select_related('tenant').first()

        if lease:
            occupied += 1
            total_expected += lease.rent_amount or Decimal('0')

            last_payment = Payment.objects.filter(
                invoice__lease=lease, status='confirmed'
            ).order_by('-paid_at').first()

            from apps.payments.models import Invoice
            arrears = Invoice.objects.filter(
                lease=lease,
                status__in=['pending', 'overdue', 'partially_paid'],
            ).aggregate(
                a=Max('amount_due')
            )
            # Compute proper arrears sum
            from django.db.models import Sum as _Sum
            arr_agg = Invoice.objects.filter(
                lease=lease,
                status__in=['pending', 'overdue', 'partially_paid'],
            ).aggregate(due=_Sum('amount_due'), paid=_Sum('amount_paid'))
            arrears_val = (arr_agg['due'] or Decimal('0')) - (arr_agg['paid'] or Decimal('0'))
            total_arrears += arrears_val

            rows.append([
                unit.unit_number,
                unit.floor or '—',
                unit.unit_type or '—',
                'Occupied',
                lease.tenant.get_full_name(),
                lease.tenant.phone_number,
                _fmt_money(lease.rent_amount),
                _fmt_date(last_payment.paid_at.date()) if last_payment else 'None',
                _fmt_money(arrears_val) if arrears_val > 0 else '—',
            ])
        else:
            rows.append([
                unit.unit_number,
                unit.floor or '—',
                unit.unit_type or '—',
                'Vacant',
                '—', '—', '—', '—', '—',
            ])

    vacant = len(units) - occupied

    buffer = io.BytesIO()
    doc = _doc(buffer)
    story = []

    story.append(_header_para("Rent Roll"))
    story.append(_sub_para(
        f"Property: {prop.name}  |  As of: {date.today().strftime('%d %b %Y')}"
    ))
    story.append(_hr())

    story.append(_section("Unit Summary"))
    table_data = [['Unit', 'Floor', 'Type', 'Status', 'Tenant', 'Phone',
                   'Rent', 'Last Paid', 'Arrears']] + rows
    t = Table(table_data, colWidths=[1.5 * cm, 1.3 * cm, 2 * cm, 2 * cm,
                                     3.5 * cm, 3 * cm, 2.5 * cm, 2.5 * cm, 2.5 * cm])
    t.setStyle(_table_style())
    story.append(t)

    story.append(Spacer(1, 0.4 * cm))
    story.append(_section("Portfolio Summary"))
    summary_data = [
        ['Metric', 'Value'],
        ['Total Units', str(len(units))],
        ['Occupied', str(occupied)],
        ['Vacant', str(vacant)],
        ['Occupancy Rate', f"{round(occupied / len(units) * 100, 1) if units else 0}%"],
        ['Total Monthly Expected', _fmt_money(total_expected)],
        ['Total Arrears', _fmt_money(total_arrears)],
    ]
    st = Table(summary_data, colWidths=[8 * cm, 8 * cm])
    st.setStyle(_table_style())
    story.append(st)

    doc.build(story)
    return buffer.getvalue()
