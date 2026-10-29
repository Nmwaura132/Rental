import calendar

import django.utils.timezone
from django.db import migrations, models


def backfill(apps, schema_editor):
    """The month end each reading closes, or the day it was typed in if that
    was earlier: the closest honest date for readings taken before this."""
    MeterReading = apps.get_model("properties", "MeterReading")
    for reading in MeterReading.objects.all():
        month_end = reading.period.replace(
            day=calendar.monthrange(reading.period.year, reading.period.month)[1]
        )
        entered = django.utils.timezone.localtime(reading.recorded_at).date()
        reading.read_on = min(month_end, entered)
        reading.save(update_fields=["read_on"])


class Migration(migrations.Migration):
    dependencies = [
        ("properties", "0009_meter_reading"),
    ]

    operations = [
        migrations.AddField(
            model_name="meterreading",
            name="read_on",
            field=models.DateField(default=django.utils.timezone.localdate),
        ),
        migrations.RunPython(backfill, migrations.RunPython.noop),
    ]
