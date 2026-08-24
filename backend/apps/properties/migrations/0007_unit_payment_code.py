import random
import re
import string

from django.db import migrations, models


_PAYMENT_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def _slugify(unit_number):
    return re.sub(r"[^A-Z0-9]", "", unit_number.upper())


def backfill_payment_codes(apps, schema_editor):
    """
    Split the old unit_number (which already carries a random suffix, e.g.
    "G1-K3P9") back into a clean unit_number ("G1") and a payment_code
    ("G1K3P9" or similar). Existing units already have a random,
    globally-unique suffix baked in, so reusing it as the payment_code is
    both correct and non-destructive: the code tenants already have on past
    invoices/SMS keeps working.
    """
    Unit = apps.get_model("properties", "Unit")
    used_codes = set()

    for unit in Unit.objects.all().order_by("id"):
        raw = unit.unit_number
        match = re.match(r"^(.*)-([A-Z0-9]{4})$", raw)
        if match:
            clean_number, old_suffix = match.group(1), match.group(2)
        else:
            clean_number, old_suffix = raw, None

        code = _slugify(raw)[:12] or f"UNIT{unit.pk}"
        if old_suffix:
            # Reuse the existing suffix as the code so nothing already
            # printed on an invoice or sent by SMS stops working.
            code = _slugify(raw)[:12]

        attempt = code
        tries = 0
        while attempt in used_codes:
            tries += 1
            suffix = "".join(random.choices(_PAYMENT_CODE_ALPHABET, k=4))
            attempt = f"{code[:7]}{suffix}"[:12]
            if tries > 20:
                raise RuntimeError(f"Could not derive a unique payment_code for unit {unit.pk}.")
        code = attempt
        used_codes.add(code)

        unit.unit_number = clean_number
        unit.payment_code = code
        unit.save(update_fields=["unit_number", "payment_code"])


def reverse_backfill(apps, schema_editor):
    """
    Restore the old "<unit_number>-<suffix>" shape by re-appending the last
    4 chars of payment_code, so a rollback doesn't strand rows on a
    unit_number that no longer round-trips to the same payment_code.
    """
    Unit = apps.get_model("properties", "Unit")
    for unit in Unit.objects.all().order_by("id"):
        suffix = (unit.payment_code or "")[-4:].rjust(4, "0")
        base = str(unit.unit_number)[:14]
        unit.unit_number = f"{base}-{suffix}"
        unit.save(update_fields=["unit_number"])


class Migration(migrations.Migration):
    dependencies = [
        ("properties", "0006_alter_unit_unique_together_alter_unit_unit_number_and_more"),
    ]

    operations = [
        # WHY this must come before the backfill: 0006 put a global UNIQUE on
        # unit_number to solve M-Pesa matching. The backfill below strips the
        # random suffix back off ("101-JT5P" -> "101"), which immediately
        # collides across properties that legitimately share a plain number
        # like "101". The global constraint has to be gone before that write.
        migrations.AlterField(
            model_name="unit",
            name="unit_number",
            field=models.CharField(max_length=20),
        ),
        migrations.AddField(
            model_name="unit",
            name="payment_code",
            field=models.CharField(max_length=12, null=True),
        ),
        migrations.RunPython(backfill_payment_codes, reverse_backfill),
        migrations.AlterField(
            model_name="unit",
            name="payment_code",
            field=models.CharField(max_length=12, unique=True, db_index=True),
        ),
        migrations.AddConstraint(
            model_name="unit",
            constraint=models.UniqueConstraint(
                fields=("property", "unit_number"), name="unit_number_unique_per_property"
            ),
        ),
    ]
