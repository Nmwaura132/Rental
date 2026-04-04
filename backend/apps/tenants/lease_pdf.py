"""
Generates a Kenya-compliant residential tenancy agreement PDF using ReportLab.
Covers requirements under: Rent Restriction Act (Cap 296), Law of Contract Act (Cap 23).
"""
import io
from datetime import date
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable
)


def _style(base, **kwargs):
    s = ParagraphStyle(base + '_custom', parent=getSampleStyleSheet()[base], **kwargs)
    return s


def generate_lease_pdf(lease) -> bytes:
    """Return PDF bytes for the given Lease instance."""
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=2.5 * cm,
        rightMargin=2.5 * cm,
        topMargin=2 * cm,
        bottomMargin=2 * cm,
    )

    tenant = lease.tenant
    unit = lease.unit
    prop = unit.property
    landlord = prop.owner

    styles = getSampleStyleSheet()
    title_style = _style('Title', fontSize=16, spaceAfter=4, textColor=colors.HexColor('#1a237e'))
    subtitle_style = _style('Normal', fontSize=10, textColor=colors.grey, alignment=TA_CENTER, spaceAfter=12)
    heading_style = _style('Heading2', fontSize=11, textColor=colors.HexColor('#1a237e'), spaceBefore=14, spaceAfter=4)
    body_style = _style('Normal', fontSize=10, leading=16, alignment=TA_JUSTIFY, spaceAfter=6)
    bold_body = _style('Normal', fontSize=10, leading=16, fontName='Helvetica-Bold')

    def hr():
        return HRFlowable(width="100%", thickness=0.5, color=colors.HexColor('#c5cae9'), spaceAfter=8, spaceBefore=4)

    def clause(number, title, text):
        return [
            Paragraph(f"{number}. {title}", heading_style),
            Paragraph(text, body_style),
        ]

    # ── Format helpers ────────────────────────────────────────────────────────
    def fmt_date(d):
        if d is None:
            return '—'
        if isinstance(d, str):
            try:
                d = date.fromisoformat(d)
            except ValueError:
                return d
        return d.strftime('%d %B %Y')

    def fmt_money(amount):
        try:
            return f"KES {float(amount):,.2f}"
        except (TypeError, ValueError):
            return f"KES {amount}"

    # ── Derived values ────────────────────────────────────────────────────────
    property_address = ', '.join(filter(None, [prop.name, prop.address, prop.town, prop.county, 'Kenya']))
    landlord_name = landlord.get_full_name()
    landlord_phone = landlord.phone_number
    tenant_name = tenant.get_full_name()
    tenant_phone = tenant.phone_number
    tenant_id = tenant.national_id or '—'
    unit_desc = f"Unit {unit.unit_number}, {prop.name}"
    rent = fmt_money(lease.rent_amount)
    deposit = fmt_money(lease.deposit_amount)
    start = fmt_date(lease.start_date)
    end = fmt_date(lease.end_date) if lease.end_date else 'Month-to-month (no fixed end date)'
    today = fmt_date(date.today())

    story = []

    # ── Header ────────────────────────────────────────────────────────────────
    story.append(Paragraph("RESIDENTIAL TENANCY AGREEMENT", title_style))
    story.append(Paragraph("Republic of Kenya — Governed by the Rent Restriction Act (Cap 296)", subtitle_style))
    story.append(hr())

    # ── Parties table ─────────────────────────────────────────────────────────
    story.append(Paragraph("PARTIES", heading_style))
    parties_data = [
        ['', 'LANDLORD', 'TENANT'],
        ['Full Name', landlord_name, tenant_name],
        ['Phone', landlord_phone, tenant_phone],
        ['National ID', landlord.national_id or '—', tenant_id],
    ]
    parties_table = Table(parties_data, colWidths=[3.5 * cm, 7 * cm, 7 * cm])
    parties_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1a237e')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('PADDING', (0, 0), (-1, -1), 6),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.HexColor('#e8eaf6'), colors.white]),
        ('GRID', (0, 0), (-1, -1), 0.3, colors.HexColor('#c5cae9')),
    ]))
    story.append(parties_table)
    story.append(Spacer(1, 0.4 * cm))

    # ── Property & terms summary table ────────────────────────────────────────
    story.append(Paragraph("PROPERTY & TERMS SUMMARY", heading_style))
    summary_data = [
        ['Property', property_address],
        ['Unit', unit_desc],
        ['Tenancy Start', start],
        ['Tenancy End', end],
        ['Monthly Rent', rent],
        ['Security Deposit', deposit],
        ['Rent Due Date', 'On or before the 5th of each month'],
        ['Notice Period', '30 days written notice by either party'],
    ]
    summary_table = Table(summary_data, colWidths=[4.5 * cm, 13 * cm])
    summary_table.setStyle(TableStyle([
        ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('PADDING', (0, 0), (-1, -1), 6),
        ('ROWBACKGROUNDS', (0, 0), (-1, -1), [colors.HexColor('#e8eaf6'), colors.white]),
        ('GRID', (0, 0), (-1, -1), 0.3, colors.HexColor('#c5cae9')),
    ]))
    story.append(summary_table)
    story.append(Spacer(1, 0.4 * cm))
    story.append(hr())

    # ── Clauses ───────────────────────────────────────────────────────────────
    story += clause(
        1, "LEASE PERIOD",
        f"This Agreement commences on <b>{start}</b> and continues until <b>{end}</b>. "
        f"Unless terminated earlier in accordance with this Agreement, the tenancy shall "
        f"automatically revert to a month-to-month arrangement upon expiry unless renewed in writing."
    )

    story += clause(
        2, "RENT PAYMENT",
        f"The Tenant agrees to pay a monthly rent of <b>{rent}</b> (Kenya Shillings) on or before "
        f"the <b>5th day</b> of each calendar month. Payment shall be made via M-Pesa Paybill or "
        f"such other method as agreed in writing. A late payment fee of <b>KES 500</b> per week "
        f"shall apply for any rent not received by the 10th of the month."
    )

    story += clause(
        3, "SECURITY DEPOSIT",
        f"The Tenant has paid a security deposit of <b>{deposit}</b>. This deposit shall be held "
        f"by the Landlord and returned within <b>30 days</b> of vacating, less any deductions for "
        f"unpaid rent, utility charges, or damage beyond fair wear and tear. The deposit shall not "
        f"be applied as rent payment."
    )

    story += clause(
        4, "LANDLORD OBLIGATIONS",
        "The Landlord shall: (a) ensure the premises are in a habitable condition at the commencement "
        "of the tenancy; (b) maintain the structure, roof, and essential services including water "
        "supply and drainage; (c) carry out necessary repairs within a reasonable time upon written "
        "notice from the Tenant; (d) provide quiet enjoyment of the premises without unlawful "
        "interference; (e) give at least 24 hours' notice before entering the premises."
    )

    story += clause(
        5, "TENANT OBLIGATIONS",
        "The Tenant shall: (a) pay rent and all utility charges promptly; (b) keep the premises "
        "clean and in good condition; (c) not make structural alterations without written consent; "
        "(d) not sub-let or assign the tenancy without written consent; (e) not use the premises "
        "for illegal purposes; (f) report any damage or maintenance issues promptly in writing; "
        "(g) vacate the premises in the same condition as received, subject to fair wear and tear."
    )

    story += clause(
        6, "TERMINATION & NOTICE",
        "Either party may terminate this Agreement by giving <b>30 days' written notice</b>. "
        "In the event of material breach by the Tenant (including non-payment of rent for 2 or "
        "more months), the Landlord may issue a 7-day notice to remedy, after which termination "
        "proceedings may commence under the Rent Restriction Act (Cap 296). "
        "Notices shall be deemed delivered when sent via SMS or WhatsApp to the registered phone number."
    )

    story += clause(
        7, "RENT INCREASES",
        "The Landlord may review rent not more than once per year, with a minimum of "
        "<b>3 months' written notice</b> as required under Kenya law. Any increase shall be "
        "reasonable and in line with prevailing market rates."
    )

    story += clause(
        8, "UTILITIES & SERVICES",
        "The Tenant shall be responsible for payment of electricity (KPLC), water, garbage "
        "collection, and any other utility charges applicable to the unit, unless otherwise "
        "agreed in writing. Failure to pay utility bills that result in disconnection shall "
        "constitute a breach of this Agreement."
    )

    story += clause(
        9, "DISPUTE RESOLUTION",
        "In the event of a dispute arising from this Agreement, the parties shall first attempt "
        "resolution through good-faith negotiation. Failing that, the matter shall be referred to "
        "mediation before being escalated to the Business Premises Rent Tribunal or a court of "
        "competent jurisdiction in Kenya."
    )

    story += clause(
        10, "GOVERNING LAW",
        "This Agreement is governed by the laws of Kenya, including the Rent Restriction Act "
        "(Cap 296), the Law of Contract Act (Cap 23), and any other applicable legislation. "
        "Any clause in this Agreement that is contrary to Kenya law shall be severable and "
        "shall not affect the validity of the remaining provisions."
    )

    story.append(hr())

    # ── Signature block ───────────────────────────────────────────────────────
    story.append(Paragraph("SIGNATURES", heading_style))
    story.append(Paragraph(
        "By signing below, both parties confirm they have read, understood, and agree to be "
        "bound by the terms of this Agreement.",
        body_style,
    ))
    story.append(Spacer(1, 0.6 * cm))

    sig_data = [
        ['LANDLORD', '', 'TENANT', ''],
        [f'Name: {landlord_name}', '', f'Name: {tenant_name}', ''],
        ['', '', '', ''],
        ['Signature: ___________________', '', 'Signature: ___________________', ''],
        [f'Date: {today}', '', f'Date: {today}', ''],
        [f'Phone: {landlord_phone}', '', f'Phone: {tenant_phone}', ''],
    ]
    sig_table = Table(sig_data, colWidths=[8 * cm, 0.5 * cm, 8 * cm, 0.5 * cm])
    sig_table.setStyle(TableStyle([
        ('FONTNAME', (0, 0), (0, 0), 'Helvetica-Bold'),
        ('FONTNAME', (2, 0), (2, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    story.append(sig_table)

    story.append(Spacer(1, 0.4 * cm))
    story.append(hr())
    story.append(Paragraph(
        f"Document generated on {today} by Rental Manager System. "
        f"This is a legally binding agreement under the laws of Kenya.",
        _style('Normal', fontSize=8, textColor=colors.grey, alignment=TA_CENTER),
    ))

    doc.build(story)
    return buffer.getvalue()
