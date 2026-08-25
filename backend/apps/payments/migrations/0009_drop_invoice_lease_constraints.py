from django.db import migrations


class Migration(migrations.Migration):
    """Drop Invoice's lease-named constraint and index BEFORE the rename.

    WHY before rather than after: Django's RenameField updates unique_together
    but not the field names recorded inside Meta.constraints / Meta.indexes.
    Once the field is called "tenancy", these two objects still describe a field
    called "lease", and RemoveConstraint/RemoveIndex raise FieldDoesNotExist
    trying to resolve it. Removing them while the field is still "lease" keeps
    the whole thing inside ordinary ORM operations.

    WHY the temporary index: MySQL requires an index on the child column of a
    foreign key and refuses to drop the last one ("Cannot drop index ... needed
    in a foreign key constraint"). Between these two removals nothing else
    covers invoices.lease_id, so a throwaway index stands in until the renamed
    replacements are added in 0010. It is deliberately kept out of Django's
    state — it exists only to satisfy MySQL for the length of the rename.
    """

    dependencies = [
        ("payments", "0008_alter_bankpaymentnotification_transaction_ref_and_more"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunSQL(
                    sql="CREATE INDEX `tmp_invoices_lease_fk` ON `invoices` (`lease_id`);",
                    reverse_sql="DROP INDEX `tmp_invoices_lease_fk` ON `invoices`;",
                ),
            ],
            state_operations=[],
        ),
        migrations.RemoveConstraint(
            model_name="invoice",
            name="invoice_lease_period_unique",
        ),
        migrations.RemoveIndex(
            model_name="invoice",
            name="invoices_lease_i_dec1b5_idx",
        ),
    ]
