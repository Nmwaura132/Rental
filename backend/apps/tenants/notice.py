"""When a tenant must be out, under the landlord's tenancy agreement.

The agreement lets either party end the tenancy with one month's written
notice, and says the tenant "should vacate the premises before the
commencement of the next payment month", failing which the deposit is
non-refundable.

Rent is paid in advance for each month, so the tenant leaves at the end of a
month they have already paid for. Notice given on 10 September runs out on
10 October; the next payment month after that is November, so they leave by
31 October. That is always the last day of the month after the one the notice
was given in, however early or late in the month it was given.
"""
from __future__ import annotations

from datetime import date, timedelta


def vacate_by(given_on: date) -> date:
    first_of_month_after_next = (given_on.replace(day=1) + timedelta(days=62)).replace(day=1)
    return first_of_month_after_next - timedelta(days=1)
