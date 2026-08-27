"""Generates the landlord's tenancy agreement as a PDF.

This reproduces the agreement the landlord actually uses, with Kasa filling the
blanks that were previously dotted lines — parties, property, house number,
rent, deposit, service charge and the paybill details.

WHY it is not a generic template: an earlier version invented terms that were
not in the landlord's agreement at all, including a KES 500 weekly late fee, and
cited the Rent Restriction Act (Cap 296) and the Business Premises Rent Tribunal.
This is a document tenants sign, so it states the landlord's terms and nothing
else. Any change here changes a contract.
"""
import io
from datetime import date

from django.conf import settings
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (
    HRFlowable,
    ListFlowable,
    ListItem,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
)

# Shown where a value is genuinely unknown, matching the dotted lines the
# landlord's own form uses, so the gap can be completed by hand.
BLANK = "…" * 12


def _style(base, **kwargs):
    return ParagraphStyle(base + "_custom", parent=getSampleStyleSheet()[base], **kwargs)


def _ordinal(n: int) -> str:
    if 11 <= (n % 100) <= 13:
        return f"{n}th"
    return f"{n}{ {1: 'st', 2: 'nd', 3: 'rd'}.get(n % 10, 'th') }"


def generate_tenancy_pdf(tenancy) -> bytes:
    """Return PDF bytes for the given Tenancy instance."""
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=2.5 * cm,
        rightMargin=2.5 * cm,
        topMargin=2 * cm,
        bottomMargin=2 * cm,
    )

    tenant = tenancy.tenant
    unit = tenancy.unit
    prop = unit.property
    landlord = prop.owner

    title_style = _style("Title", fontSize=15, spaceAfter=2)
    centre = _style("Normal", fontSize=10, alignment=TA_CENTER, spaceAfter=10)
    body = _style("Normal", fontSize=10, leading=15, alignment=TA_JUSTIFY, spaceAfter=8)
    lead = _style("Normal", fontSize=10, leading=15, spaceAfter=6)
    sub = _style("Normal", fontSize=10, leading=15, alignment=TA_JUSTIFY, spaceAfter=4)

    def money(amount):
        try:
            return f"Kshs. {float(amount):,.0f}"
        except (TypeError, ValueError):
            return BLANK

    signed_on = tenancy.start_date or date.today()

    landlord_name = landlord.get_full_name().strip() or BLANK
    tenant_name = tenant.get_full_name().strip() or BLANK
    # The landlord's form reads "known as ______ APARTMENTS", so strip a
    # trailing "Apartments" from the stored name rather than printing it twice.
    estate = prop.name.strip()
    if estate.lower().endswith("apartments"):
        estate = estate[: -len("apartments")].strip()

    service_charge = (
        prop.charges.filter(charge_type="service", is_active=True)
        .values_list("unit_price", flat=True)
        .first()
    )
    paybill = getattr(settings, "MPESA_SHORTCODE", "") or BLANK

    story = []

    story.append(Paragraph("<b>TENANCY AGREEMENT</b>", title_style))
    story.append(
        Paragraph(
            f"This TENANCY AGREEMENT is made this <b>{_ordinal(signed_on.day)}</b> "
            f"day of <b>{signed_on.strftime('%B')} {signed_on.year}</b>",
            centre,
        )
    )
    story.append(Paragraph("<b>BETWEEN:-</b>", lead))
    story.append(Paragraph(f"<b>PARTIES:</b> The Landlord: <b>{landlord_name}</b>", lead))
    story.append(Paragraph("<b>AND</b>", lead))
    story.append(Paragraph(f"The Tenant: <b>{tenant_name}</b>", lead))
    story.append(Spacer(1, 0.2 * cm))
    story.append(Paragraph("<b>WHEREAS</b>", lead))
    story.append(
        Paragraph(
            f"The Landlord is the registered Owner of ALL THAT premises known as "
            f"<b>{estate or BLANK} APARTMENTS</b> situated in "
            f"{prop.county.strip() or 'Nairobi'} County. (hereafter referred to as "
            f"“the property”).",
            body,
        )
    )
    story.append(
        Paragraph(
            f"The Landlord is desirous of renting and the Tenant agrees to rent House "
            f"No. <b>{unit.unit_number}</b> on the terms and conditions set out in this "
            f"Agreement.",
            body,
        )
    )
    story.append(HRFlowable(width="100%", thickness=0.5, color=colors.grey, spaceAfter=8))
    story.append(Paragraph("<b>NOW THIS AGREEMENT WITNESSETH AS FOLLOWS:</b>", lead))

    obligations = [
        "To maintain the general cleanliness and well being of the premises as required "
        "by the Public Health Officers, Agent and other statutory bodies as the law may "
        "at the time direct.",
        "To keep the premises and fixtures therein in good, clean and tenantable "
        "condition during the subsistence of the tenancy.",
        "To promptly report to the Landlord/Agent, any damages leakages or defects to "
        "the property, electricity or water connections.",
        "Not to keep pets or other domestic animals upon the premises.",
        "Not to commit or cause any acts of annoyance (eg. Preaching, loud music, etc.) "
        "or nuisance to the landlord, Agent or neighbours, or commit any acts which may "
        "cause damage to the wellbeing of the premises.",
        "To maintain good relationship with the Landlord, Agent, Co-tenants and "
        "neighbours and in case of any quarrels or misunderstanding the same should "
        "promptly be reported to the Agent or other relevant authorities.",
        f"To pay the service charge of {money(service_charge) if service_charge is not None else 'Ksh. ' + BLANK} "
        "being payment for communal upkeep, and general maintenance at the end of each "
        "month.",
        "Not to sublet the premises without the Landlord’s prior consent or authority.",
        "Not to make any alterations adjustments or additions to the demised premises, "
        "or whatsoever erect any fixtures thereon, or drive any nails, screws, bolts or "
        "wedges in the floor, walls, ceiling or fixtures without the Landlords or "
        "Agent’s written consent. In case of any damages by burglars or thieves, the "
        "tenant shall be responsible for repairs in respect thereof.",
    ]

    clauses = [
        f"The monthly rent payable by the Tenant in respect of the said premises shall "
        f"be Kenya Shillings <b>{money(tenancy.rent_amount)}</b> which rent shall be "
        f"payable in advance on or before the 5th day of every month without any "
        f"deductions whatsoever.",
        f"The Tenant, shall at the execution of this agreement and before entering the "
        f"premises in issue pay a rent deposit of <b>{money(tenancy.deposit_amount)}</b> "
        f"Or equivalent to One (1) month rent. Deposit is refundable upon giving one [1] "
        f"month notice and the Tenant leaving the premises, less any outstanding arrears, "
        f"charges on repairs or bills.",
        None,  # placeholder — the obligations list is inserted here
        "The Tenant shall upon reasonable time and notice grant the Landlord or Agent "
        "access to the demised premises, to inspect or do any of the following, to "
        "inspect the premises, to show other prospective Tenants around the premises and "
        "to carry out any repairs, additions, alterations or other works upon the "
        "premises or part thereof.",
        "The tenant shall use the premises exclusively as a dwelling place and not for "
        "any other purpose or business.",
        "Upon termination of the Tenancy, the Tenant shall be under obligation, to "
        "repaint the interior of the premises with two coats of water paint and one coat "
        "of plastic paint to the satisfaction of the Landlord, and the repainting shall "
        "be done with paints of similar colour, quality and scheme as was the case at "
        "the time of initial occupation of the premises, at the cost of the tenant.",
        "The rent deposit shall exclusively be applied as security to the Landlord and "
        "shall not in anyway whatsoever stand for or be computed as rent payable.",
        "All tenants must be informed that deadline for rent payment is 5th day of every "
        "month failure of payment may result in the closure of the house.",
        "Either party may terminate this Tenancy Agreement by issuing the opposite party "
        "with a one month’s written notice. The tenant should vacate the premises before "
        "the commencement of the next payment month. Failure to which the deposit shall "
        "be non-refundable.",
        "It shall generally be presumed for all intents and purposes, that prior to the "
        "execution of this agreement, the Tenant has viewed the demised premises and "
        "satisfied himself/herself regarding the condition and suitability thereof.",
        "The Tenant shall at all times render maximum cooperation to the Landlord and/or "
        "Agent, by inter alia, paying rent promptly, and maintaining the premises in "
        "good, tenantable condition.",
        "Any change of mind on occupying a premise that has been booked, a 20% levy will "
        "be deducted from the deposit.",
        "The Landlord or Agent shall not be responsible for any acts of theft, or loss "
        "upon the premises during the subsistence of the tenancy.",
        "Nothing shall bar the Landlord or Agent from instituting civil or criminal "
        "proceedings against the Tenant in the event of malicious damage to or "
        "destruction of the premises or fixtures thereon.",
        "The Landlord or Agent shall guarantee the Tenant comfort, cooperation, and "
        "peaceful occupation of the premises.",
        f"The rent shall be paid through the landlord’s bank via Paybill No. "
        f"<b>{paybill}</b> Account No. <b>{unit.payment_code}</b>, the bank message "
        f"should be presented to the Landlord/Agent for which an official receipt shall "
        f"be acknowledged.",
        "The Landlord may collect, use, store and disclose the Tenant’s personal "
        "information as reasonably necessary to manage the tenancy, collect rent, provide "
        "services, comply with the law and protect the property. The Landlord shall "
        "handle such information in accordance with the applicable data protection laws "
        "and shall take reasonable steps to keep it secure.",
        "The Tenant shall abide with such rules and regulations as may from time to time "
        "be issued by the Landlord or Agent for the better maintenance, management and "
        "administration of the demised premises.",
        "This agreement shall for all intents and purposes be governed by the Law Society "
        "of Kenya rules and regulations pertaining thereto, The Law of Contract Act "
        "[Cap 23 Laws of Kenya] alongside other relevant Laws of Kenya regarding "
        "contracts and agreements.",
    ]

    number = 0
    for text in clauses:
        number += 1
        if text is None:
            story.append(
                Paragraph(f"{number}. The Tenant shall be under obligation:-", body)
            )
            story.append(
                ListFlowable(
                    [ListItem(Paragraph(o, sub), leftIndent=18) for o in obligations],
                    bulletType="a",
                    bulletFormat="(%s)",
                    leftIndent=18,
                )
            )
            story.append(Spacer(1, 0.2 * cm))
            continue
        story.append(Paragraph(f"{number}. {text}", body))

    story.append(Spacer(1, 0.3 * cm))
    story.append(
        Paragraph(
            "IN WITNESS WHEREOF, the parties’ hereinabove execute this agreement the "
            "day, month and year hereinabove written.",
            body,
        )
    )
    story.append(Spacer(1, 0.5 * cm))

    # Signature lines stay blank: the document is printed to be signed by hand.
    story.append(Paragraph("Signed by the Landlord", lead))
    story.append(Paragraph(f"Name: <b>{landlord_name}</b>", lead))
    story.append(Paragraph(f"Signature {'_' * 34}", lead))
    story.append(Spacer(1, 0.4 * cm))
    story.append(Paragraph("SIGNED by the Tenant", lead))
    story.append(Paragraph(f"Name: <b>{tenant_name}</b>", lead))
    story.append(Paragraph(f"Signature {'_' * 34}", lead))
    story.append(Spacer(1, 0.5 * cm))
    story.append(Paragraph("In the presence of:", lead))
    story.append(Paragraph(f"Name: {'_' * 40}", lead))
    story.append(Paragraph(f"Signature {'_' * 34}", lead))

    doc.build(story)
    return buffer.getvalue()
