from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("properties", "0004_alter_property_options_alter_unit_options"),
    ]

    operations = [
        migrations.CreateModel(
            name="PropertyCharge",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("charge_type", models.CharField(
                    choices=[
                        ("water", "Water"),
                        ("electricity", "Electricity"),
                        ("garbage", "Garbage / Refuse"),
                        ("service", "Service Charge"),
                        ("security", "Security"),
                        ("sewer", "Sewerage"),
                        ("other", "Other"),
                    ],
                    max_length=20,
                )),
                ("name", models.CharField(max_length=80)),
                ("billing_method", models.CharField(
                    choices=[("metered", "Metered (per unit)"), ("flat", "Flat Fee")],
                    default="flat",
                    max_length=10,
                )),
                ("unit_price", models.DecimalField(decimal_places=2, max_digits=8)),
                ("is_active", models.BooleanField(default=True)),
                ("property", models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name="charges",
                    to="properties.property",
                )),
            ],
            options={
                "db_table": "property_charges",
                "ordering": ["charge_type"],
                "unique_together": {("property", "charge_type")},
            },
        ),
    ]
