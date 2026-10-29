from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("payments", "0017_kcb_number_unique_on_mysql"),
    ]

    operations = [
        migrations.AddField(
            model_name="invoicelineitem",
            name="previous_read_on",
            field=models.DateField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="invoicelineitem",
            name="current_read_on",
            field=models.DateField(blank=True, null=True),
        ),
    ]
