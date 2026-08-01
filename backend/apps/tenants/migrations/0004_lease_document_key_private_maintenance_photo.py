import apps.core.storage_backends
from django.db import migrations, models


def preserve_legacy_lease_documents(apps, schema_editor):
    Lease = apps.get_model("tenants", "Lease")
    for lease in Lease.objects.filter(notes__contains="[Lease PDF]").iterator():
        kept_lines = []
        document_key = ""
        for line in lease.notes.splitlines():
            if line.startswith("[Lease PDF] ") and "/leases/" in line:
                document_key = f"legacy:leases/{line.split('/leases/', 1)[1]}"
            else:
                kept_lines.append(line)
        if document_key:
            lease.document_key = document_key
            lease.notes = "\n".join(kept_lines).strip()
            lease.save(update_fields=["document_key", "notes"])


def preserve_legacy_maintenance_photos(apps, schema_editor):
    MaintenanceRequest = apps.get_model("tenants", "MaintenanceRequest")
    for request in MaintenanceRequest.objects.exclude(photo="").iterator():
        if request.photo and not request.photo.name.startswith("legacy:"):
            request.photo.name = f"legacy:public/{request.photo.name}"
            request.save(update_fields=["photo"])


class Migration(migrations.Migration):
    dependencies = [
        ("tenants", "0003_maintenancenote"),
    ]

    operations = [
        migrations.AddField(
            model_name="lease",
            name="document_key",
            field=models.CharField(blank=True, max_length=500),
        ),
        migrations.AlterField(
            model_name="maintenancerequest",
            name="photo",
            field=models.ImageField(
                blank=True,
                null=True,
                storage=apps.core.storage_backends.PrivateMediaStorage,
                upload_to="maintenance/%Y/%m/",
            ),
        ),
        migrations.RunPython(
            preserve_legacy_lease_documents,
            migrations.RunPython.noop,
        ),
        migrations.RunPython(
            preserve_legacy_maintenance_photos,
            migrations.RunPython.noop,
        ),
    ]
