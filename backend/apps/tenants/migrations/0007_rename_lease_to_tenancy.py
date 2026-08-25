from django.db import migrations


class Migration(migrations.Migration):
    """Rename Lease to Tenancy, preserving every existing row.

    WHY hand-written: the autodetector reads this as "delete model Lease, create
    model Tenancy" and emits DROP + CREATE, which would discard every tenancy on
    file and orphan the invoices pointing at them. RenameModel / RenameField /
    AlterModelTable rename in place instead, so the data survives.

    Constraint and index renames are deliberately left to the follow-up
    migration that the autodetector generates on top of this one — it derives
    the correct hashed index names, which are easy to get wrong by hand.
    """

    dependencies = [
        ("tenants", "0006_alter_maintenancerequest_photo"),
    ]

    operations = [
        migrations.RenameModel(old_name="Lease", new_name="Tenancy"),
        migrations.AlterModelTable(name="tenancy", table="tenancies"),
        migrations.RenameField(
            model_name="maintenancerequest",
            old_name="lease",
            new_name="tenancy",
        ),
    ]
