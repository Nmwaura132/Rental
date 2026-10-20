from django.db import migrations, models


def fill_kcb_number(apps, schema_editor):
    PaymentAccount = apps.get_model("payments", "PaymentAccount")
    for account in PaymentAccount.objects.filter(kind="kcb_paybill"):
        account.kcb_number = account.number
        account.save(update_fields=["kcb_number"])


class Migration(migrations.Migration):
    """Make "one KCB paybill per landlord" hold in the database on MySQL.

    0016's conditional unique constraint is silently not created on MySQL
    (models.W036), so it is replaced by a unique column that is NULL for every
    account except a KCB paybill.
    """

    dependencies = [
        ("payments", "0016_payment_accounts"),
    ]

    operations = [
        migrations.RemoveConstraint(
            model_name="paymentaccount",
            name="kcb_paybill_number_unique",
        ),
        migrations.AddField(
            model_name="paymentaccount",
            name="kcb_number",
            field=models.CharField(blank=True, editable=False, max_length=12, null=True, unique=True),
        ),
        migrations.RunPython(fill_kcb_number, migrations.RunPython.noop),
    ]
