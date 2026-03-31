from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("payments", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="InvoiceLineItem",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("description", models.CharField(max_length=120)),
                ("charge_type", models.CharField(max_length=20)),
                ("previous_reading", models.DecimalField(blank=True, decimal_places=2, max_digits=10, null=True)),
                ("current_reading", models.DecimalField(blank=True, decimal_places=2, max_digits=10, null=True)),
                ("units_consumed", models.DecimalField(blank=True, decimal_places=2, max_digits=10, null=True)),
                ("unit_price", models.DecimalField(blank=True, decimal_places=2, max_digits=8, null=True)),
                ("amount", models.DecimalField(decimal_places=2, max_digits=10)),
                ("invoice", models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name="line_items",
                    to="payments.invoice",
                )),
            ],
            options={
                "db_table": "invoice_line_items",
                "ordering": ["id"],
            },
        ),
    ]
