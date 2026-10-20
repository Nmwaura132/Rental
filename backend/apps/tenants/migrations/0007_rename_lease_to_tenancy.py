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
        # WHY: payments 0001-0009 still refer to tenants.Lease, so on a fresh
        # database they must run before it is renamed. Without this, a new
        # install and CI failed at migrate. Existing databases have both
        # applied, so the added ordering changes nothing for them.
        ("payments", "0009_drop_invoice_lease_constraints"),
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
