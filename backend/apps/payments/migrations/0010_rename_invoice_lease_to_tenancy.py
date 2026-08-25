import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    """Point Invoice at the renamed Tenancy, keeping every row attached.

    Renaming the column preserves the link between each invoice and the tenancy
    it was raised against; dropping and re-adding the field would sever that and
    take the payment history with it.
    """

    dependencies = [
        ("payments", "0009_drop_invoice_lease_constraints"),
        ("tenants", "0007_rename_lease_to_tenancy"),
    ]

    operations = [
        migrations.RenameField(
            model_name="invoice",
            old_name="lease",
            new_name="tenancy",
        ),
        # RenameField renames the column but leaves the relation pointing at
        # "tenants.lease", which no longer exists after the tenants rename.
        # Splitting these leaves a state Django refuses to build.
        migrations.AlterField(
            model_name="invoice",
            name="tenancy",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.PROTECT,
                related_name="invoices",
                to="tenants.tenancy",
            ),
        ),
        migrations.AddIndex(
            model_name="invoice",
            index=models.Index(
                fields=["tenancy", "status"], name="invoices_tenancy_937a0b_idx"
            ),
        ),
        migrations.AddConstraint(
            model_name="invoice",
            constraint=models.UniqueConstraint(
                fields=("tenancy", "period_start"),
                name="invoice_tenancy_period_unique",
            ),
        ),
        # The renamed index and constraint now cover tenancy_id, so the
        # stand-in from 0009 has nothing left to do.
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunSQL(
                    sql="DROP INDEX `tmp_invoices_lease_fk` ON `invoices`;",
                    reverse_sql="CREATE INDEX `tmp_invoices_lease_fk` ON `invoices` (`tenancy_id`);",
                ),
            ],
            state_operations=[],
        ),
    ]
